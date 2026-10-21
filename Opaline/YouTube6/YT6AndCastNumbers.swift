import Foundation

/// The server's public YouTube numbers (`GET /andcast/v1/stats`, the same
/// call the andCast iPhone and TV clients make in `refreshStatistics`):
/// views per catalog item and subscribers per channel, refreshed by the
/// server once a day from the YouTube Data API. Kept on the iPod with the
/// response's ETag, so an unchanged day costs a 304.
///
/// The server also stores likes and comment counts (`yt_video_stats`) but
/// does not hand them out yet; see the report for the proposed field.
final class YT6AndCastNumbers {
    private struct Saved: Codable {
        let account: String
        let etag: String?
        let views: [String: Int]
        let subscribers: [String: Int]
    }

    static let shared = YT6AndCastNumbers()
    private static let refreshAfter: TimeInterval = 15 * 60

    private let lock = NSLock()
    private var saved: Saved?
    private var fetchedAt: Date?
    private var fetching = false

    private var file: URL {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("yt6-andcast-stats.json")
    }

    /// Changes whenever new numbers arrive.
    var stamp: String {
        lock.lock()
        defer { lock.unlock() }
        return saved?.etag ?? "\(saved?.views.count ?? 0)"
    }

    private init() {
        let data = try? Data(contentsOf: file)
        saved = data.flatMap { try? JSONDecoder().decode(Saved.self, from: $0) }
    }

    /// "12,345 views" — the count YouTube's own rows show.
    static func viewsText(_ count: Int?) -> String? {
        count.map { "\(grouped($0)) views" }
    }

    static func subscribersText(_ count: Int?) -> String? {
        count.map { "\(grouped($0)) subscribers" }
    }

    private static func grouped(_ count: Int) -> String {
        let format = NumberFormatter()
        format.numberStyle = .decimal
        format.locale = Locale(identifier: "en_US")
        return format.string(for: count) ?? "\(count)"
    }

    /// Views of an andCast item, as YouTube counted them.
    func views(item: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return saved?.account == YT6AndCastCatalog.account ? saved?.views[item] : nil
    }

    func subscribers(channel: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return saved?.account == YT6AndCastCatalog.account ? saved?.subscribers[channel] : nil
    }

    func refresh() {
        guard !fetching, YT6AndCast.isSignedIn, YT6Source.mode != .downloadedOnly else {
            return
        }
        if let fetchedAt, Date().timeIntervalSince(fetchedAt) < Self.refreshAfter {
            return
        }
        fetching = true
        YT6AndCastReach.current { [weak self] base in
            guard let self, let base, var request = YT6AndCast.api("v1/stats", base: base) else {
                self?.fetching = false
                return
            }
            let current = self.saved?.account == YT6AndCastCatalog.account ? self.saved?.etag : nil
            if let current {
                request.setValue(current, forHTTPHeaderField: "If-None-Match")
            }
            YT6AndCast.urlSession.dataTask(with: request) { data, response, _ in
                let http = response as? HTTPURLResponse
                let parsed = http?.statusCode == 200 ? data.flatMap(YT6AndCast.json) : nil
                let etag = http?.allHeaderFields.first {
                    ($0.key as? String)?.lowercased() == "etag"
                }?.value as? String
                DispatchQueue.main.async {
                    self.finish(status: http?.statusCode ?? 0, body: parsed, etag: etag)
                }
            }
            .resume()
        }
    }

    private func finish(status: Int, body: [String: Any]?, etag: String?) {
        fetching = false
        guard status == 200 || status == 304 else {
            YT6AndCast.log("stats base: HTTP \(status)")
            return
        }
        fetchedAt = Date()
        guard let body, let account = YT6AndCastCatalog.account else {
            return
        }
        let views = body["videos"] as? [String: Int] ?? [:]
        let channels = body["channels"] as? [String: [String: Any]] ?? [:]
        let subscribers = channels.compactMapValues { $0["subscribers"] as? Int }
        let next = Saved(account: account, etag: etag, views: views, subscribers: subscribers)
        lock.lock()
        saved = next
        lock.unlock()
        if let data = try? JSONEncoder().encode(next) {
            try? data.write(to: file, options: .atomic)
        }
        YT6AndCast.log("stats base: \(views.count) videos, \(subscribers.count) channels")
        NotificationCenter.default.post(name: YT6AndCastCatalog.didChangeNotification, object: nil)
    }
}
