import Foundation
import QuartzCore

/// Serves the byte-range stream's segments from `127.0.0.1` (REQUEST687).
///
/// Upstream's byte-range playlists point AVPlayer straight at googlevideo,
/// so the player opens connections of its own — and through the device's
/// proxy about half of all new connections stalled ~5.3 s. Here the media
/// playlists list one local URL per segment (`/v/init`, `/v/12`, `/a/0`…)
/// and each is fetched over `YT6.mediaSession`, i.e. the one warm connection
/// the index requests already opened. If the local server is not ready by
/// the time the playlists are built, upstream's direct playlists are used.
///
/// One download per segment however often AVPlayer asks for it, streamed
/// to the player as it arrives (`YT6SegmentStream`); requests left behind by
/// a seek and every request of the previous video are cancelled
/// (REQUEST695: one segment was fetched four times, and the last video's
/// tails kept loading 12–18 s into the next one).
final class YT6RangeProxy {
    private typealias Reply = (Data?, String) -> Void

    private struct Track {
        let url: URL
        let initBytes: Int64
        let dataStart: Int64
        let segments: [SidxSegment]
        let mime: String

        init(_ url: URL, _ format: DashFormatInfo, _ segments: [SidxSegment], mime: String) {
            self.url = url
            initBytes = Int64(format.initRangeEnd + 1)
            dataStart = Int64(format.indexRangeEnd + 1)
            self.segments = segments
            self.mime = mime
        }

        /// Bytes of `init` or of segment N, or nil for anything else.
        func range(of name: String) -> (Int64, Int64)? {
            if name == "init" {
                return (0, initBytes - 1)
            }
            guard let index = Int(name), segments.indices.contains(index) else {
                return nil
            }
            let start = dataStart + segments[index].offset
            return (start, start + segments[index].size - 1)
        }
    }

    private static var pending: [URL: YT6RangeProxy] = [:]
    private static let live = NSHashTable<YT6RangeProxy>.weakObjects()
    /// A seek: a request this many segments away from one still loading.
    private static let seekDistance = 2
    private static let lock = NSLock()
    private static var retainKey: UInt8 = 0

    private let server: LocalMediaServer
    private let headers: [String: String]
    private let state = NSLock()
    private var readyBase: URL?
    private var tracks: [String: Track] = [:]
    /// AVPlayer probes a segment (HEAD, then GET) — keep the last few.
    private var recent: [(path: String, data: Data)] = []
    private var downloads: [String: YT6SegmentStream] = [:]

    private var base: URL? {
        get {
            state.lock()
            defer {
                state.unlock()
            }
            return readyBase
        }
        set {
            state.lock()
            readyBase = newValue
            state.unlock()
        }
    }

    private init?(headers: [String: String]) {
        self.headers = headers
        var route: ((String, @escaping (Data?, String) -> Void) -> Void)?
        guard let server = LocalMediaServer(handler: { path, done in route?(path, done) }) else {
            return nil
        }
        self.server = server
        server.yt6Streamer = { [weak self] path in
            self?.stream(path)
        }
        route = { [weak self] path, done in
            guard let self else {
                done(nil, "")
                return
            }
            self.serve(path, completion: done)
        }
    }

    /// Starts a server for a stream about to be built (from
    /// `HLSPlaybackBuilder.build`); it is ready long before the indexes are.
    static func prepare(for input: HLSPlaybackBuilder.BuildInput) {
        guard YT6.isEnabled, let proxy = YT6RangeProxy(headers: input.headers) else {
            return
        }
        proxy.server.start { [weak proxy] base in
            proxy?.base = base
        }
        lock.lock()
        let previous = live.allObjects
        live.add(proxy)
        pending[input.videoURL] = proxy
        lock.unlock()
        previous.forEach { $0.cancelAll() }
    }

    /// Registers proxied media playlists on `loader` and keeps the proxy
    /// alive with it; false when there is no ready proxy for this stream.
    static func registerPlaylists(
        on loader: HLSPlaylistLoader,
        input: HLSPlaybackBuilder.BuildInput,
        video: [SidxSegment],
        audio: [SidxSegment]
    ) -> Bool {
        lock.lock()
        let proxy = pending.removeValue(forKey: input.videoURL)
        lock.unlock()
        guard let proxy, let base = proxy.base else {
            return false
        }
        proxy.tracks["v"] = Track(input.videoURL, input.videoFormat, video, mime: "video/mp4")
        proxy.tracks["a"] = Track(input.audioURL, input.audioFormat, audio, mime: "audio/mp4")
        let root = base.absoluteString
        for (path, name, segments) in [("v", "video.m3u8", video), ("a", "audio.m3u8", audio)] {
            let playlist = HLSGenerator.segmentedPlaylist(
                base: "\(root)/\(path)",
                segments: segments,
                startAt: input.startAt
            )
            loader.register(path: name, content: playlist)
        }
        objc_setAssociatedObject(loader, &retainKey, proxy, .OBJC_ASSOCIATION_RETAIN)
        AppLog.hls("range proxy on \(root)")
        return true
    }

    /// Upstream's whole-body path: HEAD, part of a segment, or a playlist
    /// path the streamer turned down. Waits on the same download.
    private func serve(_ path: String, completion: @escaping Reply) {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, let track = tracks[parts[0]] else {
            completion(nil, "")
            return
        }
        if let hit = cached(path) {
            completion(hit, track.mime)
            return
        }
        guard let stream = stream(path) else {
            completion(nil, "")
            return
        }
        stream.read(onData: { _ in }, onEnd: { body in
            completion(body, track.mime)
        })
    }

    private func cached(_ path: String) -> Data? {
        state.lock()
        defer {
            state.unlock()
        }
        return recent.last { $0.path == path }?.data
    }

    private func remember(_ path: String, _ data: Data) {
        state.lock()
        recent.append((path, data))
        if recent.count > 4 {
            recent.removeFirst()
        }
        state.unlock()
    }

    deinit {
        downloads.values.forEach { $0.cancel() }
        server.stop()
    }
}

// MARK: - Downloads

extension YT6RangeProxy {
    /// The download for a segment path — joined if one is running, started
    /// otherwise — or nil for a cached segment or an unknown path.
    private func stream(_ path: String) -> YT6SegmentStream? {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, let track = tracks[parts[0]], cached(path) == nil,
              let range = track.range(of: parts[1])
        else {
            return nil
        }
        state.lock()
        if let running = downloads[path] {
            state.unlock()
            AppLog.hls("[Speed] seg \(path) joined")
            return running
        }
        let stream = YT6SegmentStream(length: Int(range.1 - range.0 + 1), mime: track.mime)
        downloads[path] = stream
        state.unlock()
        cancelSkipped(track: parts[0], index: Int(parts[1]))
        start(stream, path: path, range: range, url: track.url)
        return stream
    }

    private func start(_ stream: YT6SegmentStream, path: String, range: (Int64, Int64), url: URL) {
        var request = URLRequest(url: YT6.mediaURL(for: url))
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("bytes=\(range.0)-\(range.1)", forHTTPHeaderField: HTTPHeader.range)
        let started = CACurrentMediaTime()
        var firstByte: Int?
        stream.read(
            onData: { _ in
                if firstByte == nil {
                    firstByte = Int((CACurrentMediaTime() - started) * 1_000)
                }
            },
            onEnd: { [weak self, weak stream] body in
                let ms = Int((CACurrentMediaTime() - started) * 1_000)
                let kb = (stream?.length ?? 0) / 1_024
                let code = stream?.statusCode ?? 0
                let first = firstByte.map { "\($0)" } ?? "-"
                AppLog.hls("[Speed] seg \(path) \(kb) KB first \(first) all \(ms) ms code \(code)")
                if code >= 400 {
                    YT6NetMetrics.forget(url)
                }
                self?.finish(path, body)
            }
        )
        stream.start(request, on: YT6.mediaSession(for: url))
    }

    private func finish(_ path: String, _ body: Data?) {
        state.lock()
        downloads.removeValue(forKey: path)
        state.unlock()
        if let body {
            remember(path, body)
        }
    }

    /// After a seek AVPlayer no longer wants what it asked for before it on
    /// the same track; those downloads only hold the connection.
    private func cancelSkipped(track: String, index: Int?) {
        guard let index else {
            return
        }
        state.lock()
        let stale = downloads.filter { path, _ in
            let parts = path.split(separator: "/")
            guard parts.count == 2, parts[0] == track, let other = Int(parts[1]) else {
                return false
            }
            return abs(other - index) > Self.seekDistance
        }
        state.unlock()
        for (path, stream) in stale {
            AppLog.hls("[Speed] seg \(path) cancelled (seek to \(track)/\(index))")
            stream.cancel()
        }
    }

    /// Every download still running — a newer video has started.
    private func cancelAll() {
        state.lock()
        let running = Array(downloads.values)
        state.unlock()
        if !running.isEmpty {
            AppLog.hls("[Speed] cancelled \(running.count) downloads of the previous video")
        }
        running.forEach { $0.cancel() }
    }
}
