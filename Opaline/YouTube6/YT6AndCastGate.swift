import Foundation

/// The one door every app request goes through (`URLSessionTransport`).
///
/// - andCast addresses get the token header and are moved to whichever
///   address answers now (artwork URLs are written with the server's
///   canonical one).
/// - «andCast only» lets nothing else out: no Innertube, no googlevideo,
///   no ytimg (REQUEST724). «Downloaded only» lets nothing out at all.
///   Refused requests fail as "not connected", which Opaline already
///   handles as offline.
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
        guard mode != .youtubeAndCast else {
            return nil
        }
        noteRefused(host, mode: mode)
        return APIError.transport(URLError(.notConnectedToInternet))
    }

    /// Thumbnail candidates: the server's artwork first for a video it
    /// has; in the local modes only that.
    static func thumbnailCandidates(for url: URL, youtube: [URL]) -> [URL] {
        let mode = YT6Source.mode
        guard mode != .downloadedOnly,
              let art = artwork(forThumbnail: url),
              mode == .andCastOnly || YT6AndCastReach.base != nil else {
            return youtube
        }
        return mode == .andCastOnly ? [art] : [art] + youtube
    }

    /// `i.ytimg.com/vi/<id>/…` of a video on the server → its artwork.
    private static func artwork(forThumbnail url: URL) -> URL? {
        guard url.host?.hasSuffix("ytimg.com") == true else {
            return nil
        }
        let parts = url.pathComponents
        guard let index = parts.firstIndex(where: { $0 == "vi" || $0 == "vi_webp" }),
              index + 1 < parts.count,
              let item = YT6AndCastCatalog.shared.item(videoId: parts[index + 1]),
              let art = YT6AndCast.artworkURL(item.id, revision: item.artwork) else {
            return nil
        }
        return URL(string: art)
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
