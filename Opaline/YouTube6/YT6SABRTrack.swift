import Foundation
import QuartzCore

/// One track of a tv.sabr download: its init segment, then segment after
/// segment in order — each one `SABRSegmentRequest` as
/// `SABRDelivery+Serving` builds it for a playlist entry (sequence from 1,
/// start time from the `sidx` durations) — written straight to its part
/// file. Everything runs on the job's queue.
final class YT6SABRTrack {
    /// APPROXIMATION: tries per segment before the job is handed to
    /// upstream's retry, which resumes from the last whole segment.
    private static let attempts = 3
    /// A segment still unanswered after this gets a second request, as the
    /// first segment after a seek does in playback (`YT6StartSegments`).
    /// APPROXIMATION: 2 s for the first byte plus the size at 1 MB/s; the
    /// log 21.10 14:00 has 0.2–1 s per 0.16–1.2 MB and one 16.8 s stall.
    private static let firstByte: TimeInterval = 2
    private static let bytesPerSecond = 1_000_000.0
    /// How often a track reports its count to the log.
    private static let logEvery = 20

    private let name: String
    private let dash: DashFormatInfo
    private let format: SabrFormatInfo
    private let other: SabrFormatInfo
    private let file: URL
    private let job: YT6SABRDownload
    private var fetcher: SABRFetcher?
    private var segments: [SidxSegment] = []
    private var starts: [Int] = []
    private var handle: FileHandle?
    private var index = 0
    private var tries = 0
    private var written: Int64 = 0
    private let started = CACurrentMediaTime()

    private var label: String { "sabr \(job.videoId) \(name)" }

    init(
        name: String,
        dash: DashFormatInfo,
        other: DashFormatInfo,
        file: URL,
        job: YT6SABRDownload
    ) {
        self.name = name
        self.dash = dash
        format = SABRDelivery.formatInfo(dash)
        self.other = SABRDelivery.formatInfo(other)
        self.file = file
        self.job = job
    }

    func start(with fetcher: SABRFetcher) {
        self.fetcher = fetcher
        if let cached = YT6PlaybackCache.initData(for: format) {
            AppLog.downloads("\(label): init from cache")
            opened(cached)
            return
        }
        requestInit()
    }

    /// Everything before the first media byte: ftyp, moov and sidx.
    private func requestInit() {
        guard job.isLive, let fetcher else {
            return
        }
        let request = SABRSegmentRequest(
            format: format,
            other: other,
            sequence: 1,
            timeMs: 0,
            initRange: dash.indexRangeEnd + 1
        )
        YT6SABRSpeed.fetchInit(request, with: fetcher) { [self] result in
            job.queue.async {
                switch result {
                case .success(let data):
                    self.opened(data)
                case .failure(let error):
                    self.retry(error, then: self.requestInit)
                }
            }
        }
    }

    private func opened(_ data: Data) {
        guard job.isLive else {
            return
        }
        guard data.count == dash.indexRangeEnd + 1,
              let segments = HLSGenerator.parseSidx(data: data), !segments.isEmpty else {
            close(with: SABRError.noInitSegment)
            return
        }
        self.segments = segments
        starts = segments.indices.map { index in
            Int(segments.prefix(index).reduce(0) { $0 + $1.duration } * 1_000)
        }
        guard position(after: data) else {
            close(with: DownloadError.storage)
            return
        }
        job.recountProgress()
        let seconds = Int(segments.reduce(0) { $0 + $1.duration })
        AppLog.downloads(
            "\(label): init \(data.count) B, \(segments.count) segments, \(seconds) s,"
                + " \(dash.contentLength) B expected, from segment \(index + 1)"
        )
        next()
    }

    /// Opens the part file where this track carries on: a fresh one starts
    /// with the init, one left by an earlier attempt is cut back to its last
    /// whole segment and continues after it.
    private func position(after initData: Data) -> Bool {
        let disk = VideoDownloader.bytesOnDisk(at: file)
        var boundary = Int64(initData.count)
        index = 0
        if disk < boundary {
            try? FileManager.default.removeItem(at: file)
            guard FileManager.default.createFile(atPath: file.path, contents: initData) else {
                return false
            }
        } else {
            while index < segments.count, boundary + segments[index].size <= disk {
                boundary += segments[index].size
                index += 1
            }
        }
        guard let handle = try? FileHandle(forWritingTo: file) else {
            return false
        }
        handle.truncateFile(atOffset: UInt64(boundary))
        self.handle = handle
        written = boundary
        return true
    }

    private func next() {
        guard job.isLive, let fetcher else {
            handle?.closeFile()
            return
        }
        guard index < segments.count else {
            done()
            return
        }
        let expected = segments[index].size
        let request = SABRSegmentRequest(
            format: format,
            other: other,
            sequence: index + 1,
            timeMs: starts[index],
            initRange: nil
        )
        let hedge = Self.firstByte + Double(expected) / Self.bytesPerSecond
        YT6SABRSpeed.fetchHedged(request, with: fetcher, after: hedge) { [self] result in
            job.queue.async {
                self.landed(result, expected: expected)
            }
        }
    }

    private func landed(_ result: Result<Data, Error>, expected: Int64) {
        guard job.isLive else {
            handle?.closeFile()
            return
        }
        switch result {
        case .failure(let error):
            retry(error, then: next)
        case .success(let data) where Int64(data.count) < expected:
            retry(SABRError.server("\(data.count) of \(expected) B"), then: next)
        case .success(let data):
            if Int64(data.count) != expected {
                AppLog.downloads(
                    "\(label) \(index + 1): \(data.count) B, sidx says \(expected) B"
                )
            }
            handle?.write(data)
            written += Int64(data.count)
            job.wrote(data.count)
            index += 1
            tries = 0
            if index.isMultiple(of: Self.logEvery) {
                AppLog.downloads(
                    "\(label): \(index)/\(segments.count) segments, \(written) B,"
                        + " \(YT6DownloadRoute.ms(since: started)) ms"
                )
            }
            next()
        }
    }

    /// Asks again after a pause that grows with each try; past the budget the
    /// job fails and upstream's retry takes over.
    private func retry(_ error: Error, then again: @escaping () -> Void) {
        tries += 1
        guard tries < Self.attempts else {
            close(with: error)
            return
        }
        AppLog.downloads("\(label) \(index + 1): \(error), try \(tries + 1)")
        job.queue.asyncAfter(deadline: .now() + Double(tries), execute: again)
    }

    private func done() {
        let seconds = Double(YT6DownloadRoute.ms(since: started)) / 1_000
        let rate = seconds > 0 ? Double(written) / 1_048_576 / seconds : 0
        AppLog.downloads(
            "\(label): \(segments.count) segments, expected \(dash.contentLength) B,"
                + " wrote \(written) B in "
                + String(format: "%.1f s (%.2f MB/s)", seconds, rate)
        )
        close(with: nil)
    }

    private func close(with error: Error?) {
        handle?.closeFile()
        handle = nil
        job.trackFinished(error)
    }
}
