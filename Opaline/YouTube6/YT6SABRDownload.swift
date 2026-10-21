import Foundation
import QuartzCore

/// A tv.sabr download (REQUEST718): the init segment and every media
/// segment of the chosen video and audio formats, fetched exactly as
/// `SABRDelivery` fetches them for AVPlayer, appended in order to
/// upstream's two part files.
///
/// `SABRDelivery`'s note: the init segment is the file's bytes up to the end
/// of `sidx`, and each segment is the next `sidx` reference, so init plus the
/// segments in order is byte for byte the file behind a direct URL — what
/// upstream's range download wrote and its passthrough mux already joins
/// into `video.mp4`. Storage and the offline player stay as they were.
extension VideoDownloader {
    /// Replaces `fetchTracks` for an option with no direct URL.
    func yt6FetchOverSABR(videoId: String, option: DownloadOption) {
        AppLog.downloads(
            "sabr \(videoId): source tv.sabr, \(option.label)"
                + " itags \(option.video.itag)+\(option.audio.itag)"
        )
        let job = YT6SABRDownload(
            videoId: videoId,
            option: option,
            downloader: self,
            parts: (videoPartFile(videoId), audioPartFile(videoId))
        )
        YT6SABRDownload.replaceCurrent(with: job)
        job.start()
    }
}

/// One video being saved over SABR: its TV `/player`, the solved stream URL
/// and one session for both tracks, which run side by side.
final class YT6SABRDownload {
    private static var current: YT6SABRDownload?
    private static let currentLock = NSLock()

    let videoId: String
    private let option: DownloadOption
    let downloader: VideoDownloader
    private let parts: (video: URL, audio: URL)
    /// The job's token when it started: a cancel swaps the downloader's.
    private let token: CancellationToken?
    private let source: InnertubeVideoSource
    /// Everything below and both tracks run here.
    let queue = DispatchQueue(label: "com.ytvlite.yt6-sabr-download")
    private var fetcher: SABRFetcher?
    private var tracks: [YT6SABRTrack] = []
    private var pending = 0
    private var ended = false
    private let started = CACurrentMediaTime()

    /// Still worth a request: not finished, failed or cancelled.
    var isLive: Bool { !ended && token?.isCancelled != true }
    private var elapsedMs: Int { YT6DownloadRoute.ms(since: started) }

    init(
        videoId: String,
        option: DownloadOption,
        downloader: VideoDownloader,
        parts: (video: URL, audio: URL)
    ) {
        self.videoId = videoId
        self.option = option
        self.downloader = downloader
        self.parts = parts
        token = downloader.cancellation
        source = YT6DownloadRoute.tvSource(apiClient: downloader.apiClient)
    }

    /// One job runs at a time; one left over from before a retry stops.
    static func replaceCurrent(with job: YT6SABRDownload) {
        currentLock.lock()
        let previous = current
        current = job
        currentLock.unlock()
        previous?.queue.async { previous?.end() }
    }

    /// The TV `/player` again: the one the options came from may be hours
    /// old by a retry, and this one also mints the PoToken the session signs
    /// its requests with. Usually from `YT6PlaybackCache`.
    func start() {
        source.fetchInfo(videoId: videoId, cancellation: nil) { [self] result in
            switch result {
            case .failure(let error):
                finish(error)
            case .success(let info):
                open(info)
            }
        }
    }

    private func open(_ info: DirectPlaybackInfo) {
        guard let url = info.serverAbrStreamingURL,
              let config = info.videoPlaybackUstreamerConfig.flatMap(SABRDelivery.decodeConfig)
        else {
            finish(SABRError.server("player response carries no SABR stream"))
            return
        }
        let video = info.allDashVideoFormats.first { $0.itag == option.video.itag }
            ?? option.video
        let audio = info.allDashAudioFormats.first {
            $0.itag == option.audio.itag && $0.xtags == option.audio.xtags
        } ?? option.audio
        AppLog.downloads("sabr \(videoId): /player in \(elapsedMs) ms, solving n")
        let signed = SABRDelivery.televisionParams(
            source.client.directURL(baseURL: url, poToken: nil), cpn: PlaybackNonce.make()
        )
        SABRDelivery.solvingThrottle(signed) { [self] solved in
            queue.async {
                self.run(url: solved, config: config, video: video, audio: audio)
            }
        }
    }

    private func run(url: URL, config: Data, video: DashFormatInfo, audio: DashFormatInfo) {
        guard isLive else {
            return
        }
        let fetcher = SABRFetcher(
            transport: downloader.transport,
            url: url,
            ustreamerConfig: config,
            identity: SABRIdentity(client: source.client, poToken: source.sabrPoToken)
        )
        self.fetcher = fetcher
        AppLog.downloads(
            "sabr \(videoId): session open in \(elapsedMs) ms,"
                + " pot \(source.sabrPoToken == nil ? "none" : "yes")"
        )
        tracks = [
            YT6SABRTrack(name: "video", dash: video, other: audio, file: parts.video, job: self),
            YT6SABRTrack(name: "audio", dash: audio, other: video, file: parts.audio, job: self)
        ]
        pending = tracks.count
        tracks.forEach { $0.start(with: fetcher) }
    }

    // MARK: - Called by the tracks, on `queue`

    func wrote(_ count: Int) {
        downloader.advance(by: Int64(count))
    }

    /// Progress from what is on disk, once a track knows where it resumes.
    func recountProgress() {
        downloader.resetProgressToDisk(videoId: videoId)
    }

    func trackFinished(_ error: Error?) {
        guard error == nil else {
            finish(error)
            return
        }
        pending -= 1
        if pending == 0 {
            finish(nil)
        }
    }

    // MARK: - Ending

    private func end() {
        ended = true
        fetcher?.stop()
        // The tracks hold the job; the job lets them go here.
        tracks.removeAll()
    }

    /// Hands the parts to upstream's mux, or the error to its retry. A job
    /// that was cancelled reports nothing: `cancel()` already cleaned up and
    /// moved on to the next one.
    private func finish(_ error: Error?) {
        queue.async { [self] in
            guard !ended else {
                return
            }
            end()
            guard token?.isCancelled != true, downloader.activeVideoId == videoId else {
                AppLog.downloads("sabr \(videoId): stopped after \(elapsedMs) ms (cancelled)")
                return
            }
            guard let error else {
                AppLog.downloads("sabr \(videoId): both tracks in \(elapsedMs) ms, muxing")
                downloader.mux(videoId: videoId, option: option, parts: parts)
                return
            }
            AppLog.downloads("sabr \(videoId): failed after \(elapsedMs) ms: \(error)")
            // The cached `/player` may be what failed; a retry asks again.
            YT6PlaybackCache.forget(videoId: videoId)
            downloader.fail(videoId: videoId, error: error)
        }
    }
}
