import Foundation

/// Serves the byte-range stream's segments from `127.0.0.1` (REQUEST687).
///
/// Upstream's byte-range playlists point AVPlayer straight at googlevideo,
/// so the player opens connections of its own — and through the device's
/// proxy about half of all new connections stalled ~5.3 s. Here the media
/// playlists list one local URL per segment (`/v/init`, `/v/12`, `/a/0`…)
/// and each is fetched over `YT6.mediaSession`, i.e. the one warm connection
/// the index requests already opened. If the local server is not ready by
/// the time the playlists are built, upstream's direct playlists are used.
final class YT6RangeProxy {
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
    private static let lock = NSLock()
    private static var retainKey: UInt8 = 0

    private let server: LocalMediaServer
    private let headers: [String: String]
    private let state = NSLock()
    private var readyBase: URL?
    private var tracks: [String: Track] = [:]
    /// AVPlayer probes a segment (HEAD, then GET) — keep the last few.
    private var recent: [(path: String, data: Data)] = []

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
        pending[input.videoURL] = proxy
        lock.unlock()
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

    private func serve(_ path: String, completion: @escaping (Data?, String) -> Void) {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count == 2, let track = tracks[parts[0]] else {
            completion(nil, "")
            return
        }
        if let hit = cached(path) {
            completion(hit, track.mime)
            return
        }
        guard let range = track.range(of: parts[1]) else {
            completion(nil, "")
            return
        }
        var request = URLRequest(url: track.url)
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.setValue("bytes=\(range.0)-\(range.1)", forHTTPHeaderField: HTTPHeader.range)
        YT6.mediaSession.dataTask(with: request) { [weak self] data, response, _ in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = code == 206 || code == 200 ? data : nil
            if let body {
                self?.remember(path, body)
            }
            completion(body, track.mime)
        }
        .resume()
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
        server.stop()
    }
}
