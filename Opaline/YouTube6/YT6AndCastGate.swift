import Foundation

/// The one door every app request goes through (`URLSessionTransport`).
///
/// - andCast addresses get the token header and are moved to whichever
///   address answers now (artwork URLs are written with the server's
///   canonical one).
/// - «andCast only» (as the owner set it, REQUEST727): the video comes
///   from andCast only, so no googlevideo media and no channel RSS polls;
///   YouTube's metadata (Innertube, ytimg, avatars, watchtime) may be
///   asked, and the screens fall back to the andCast base when it fails.
/// - «Downloaded only» lets nothing out at all.
/// Refused requests fail as "not connected", which Opaline already
/// handles as offline.
enum YT6AndCastGate {
    private static var refusedHosts = Set<String>()
    private static let lock = NSLock()

    /// nil lets the (possibly rewritten) request go; an error refuses it.
    static func admit(_ request: inout HTTPRequest) -> Error? {
        guard let host = request.url.host?.lowercased(), !isLoopback(host) else {
            return nil
        }
        let mode = YT6Source.mode
        if mode != .downloadedOnly, YT6AndCast.isOwnHost(host) {
            sign(&request)
            return nil
        }
        guard mode == .downloadedOnly || isMedia(request.url, host: host) else {
            return nil
        }
        noteRefused(host, mode: mode)
        return APIError.transport(URLError(.notConnectedToInternet))
    }

    /// Media bytes from YouTube, which «andCast only» never plays.
    private static func isMedia(_ url: URL, host: String) -> Bool {
        host.hasSuffix("googlevideo.com") || url.path.hasPrefix("/videoplayback")
            || url.path.hasPrefix("/feeds/videos.xml")
    }

    /// Thumbnail candidates: the server's artwork first for a video the
    /// server has, in every mode — it is the same picture, nearer, and
    /// stays in the image cache — YouTube's files after it.
    static func thumbnailCandidates(
        for url: URL,
        videoId: String?,
        youtube: [URL]
    ) -> [URL] {
        let own = url.host.map(YT6AndCast.isOwnHost) == true ? url : nil
        // A server that does not answer would only cost a timeout first.
        let reachable = YT6AndCastReach.base != nil || YT6Source.mode == .downloadedOnly
        let found = reachable ? artwork(videoId: videoId ?? youtubeVideo(in: url)) : nil
        guard let art = own ?? found else {
            return youtube
        }
        return [art] + youtube.filter { $0 != art }
    }

    static func artwork(videoId: String?) -> URL? {
        guard let videoId, let item = YT6AndCastCatalog.shared.item(videoId: videoId),
              let art = YT6AndCast.artworkURL(item.id, revision: item.artwork) else {
            return nil
        }
        return URL(string: art)
    }

    /// `i.ytimg.com/vi/<id>/…` → `<id>`.
    private static func youtubeVideo(in url: URL) -> String? {
        guard url.host?.hasSuffix("ytimg.com") == true else {
            return nil
        }
        let parts = url.pathComponents
        guard let index = parts.firstIndex(where: { $0 == "vi" || $0 == "vi_webp" }),
              index + 1 < parts.count else {
            return nil
        }
        return parts[index + 1]
    }

    private static func sign(_ request: inout HTTPRequest) {
        if let token = YT6AndCast.session?.token {
            request.headers["X-Emby-Token"] = token
        }
        guard let base = YT6AndCastReach.base,
              var parts = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
              parts.host?.lowercased() != base.host?.lowercased() || parts.scheme != base.scheme
        else {
            return
        }
        parts.scheme = base.scheme
        parts.host = base.host
        parts.port = base.port
        if let moved = parts.url {
            request.url = moved
        }
    }

    private static func isLoopback(_ host: String) -> Bool {
        host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private static func noteRefused(_ host: String, mode: YT6Source.Mode) {
        lock.lock()
        let first = refusedHosts.insert(host).inserted
        lock.unlock()
        if first {
            YT6AndCast.log("\(mode.title): no request to \(host)")
        }
    }
}
