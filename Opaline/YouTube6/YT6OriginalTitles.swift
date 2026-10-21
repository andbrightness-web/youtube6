import UIKit

/// Video titles as uploaded, whatever the language (REQUEST719: «названия…
/// оригинал, не переводить… не завязываться на локали»).
///
/// Lists carry a title in the request's `hl`: a creator's own translation
/// when there is one (and, signed in, possibly YouTube's machine one — to
/// be seen in the `[Lang]` log). Measured 21.10 from srv, signed out: TV
/// `/next` with `hl=ru` lists MrBeast's plN7JMbadRg as «Съешь Всё В
/// Продуктовом Магазине…» and Vlad's lT7sqCnTqWA as «Влад встретил своего
/// ЗЛОГО ДВОЙНИКА!»; with `hl=en` the Russian ilFJldLbM1Q «10 Ошибок
/// Воландеморта» comes as «10 Mistakes of Voldemort». No renderer field
/// holds the original. `/player` `videoDetails.title` and oEmbed give the
/// uploaded title at every `hl` («Eat Everything In A Grocery Store…», «I
/// Met My EVIL TWIN!»), oEmbed in ~0.2 s for ~600 bytes with no account
/// and no cookies — so rows show the list's title at once and swap in
/// oEmbed's. APPROXIMATION: 2.0.0 had one title per video (GData).
final class YT6OriginalTitles {
    static let shared = YT6OriginalTitles()

    private static let diskKey = "yt6_original_titles"
    private static let limit = 3_000

    /// Video id → uploaded title; main thread only.
    private var titles: [String: String] = [:]
    /// Insertion order, to forget the oldest past `limit`.
    private var order: [String] = []
    /// Lookups on the way, and ids oEmbed had no title for this launch
    /// (private, removed, offline) — those are not asked again.
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []
    private var waiting: [String: [(String) -> Void]] = [:]
    private var saveScheduled = false

    /// Anonymous and cookie-free: oEmbed needs no account, and nothing of
    /// the signed-in session goes with it.
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpMaximumConnectionsPerHost = 2
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    private init() {
        let stored = AppCache.shared.readDisk(
            [[String]].self, key: Self.diskKey, ttl: 60 * 86_400
        ) ?? []
        for pair in stored where pair.count == 2 {
            remember(pair[1], for: pair[0])
        }
    }

    /// Shows `title` in `label` now and the uploaded title once known.
    static func show(_ title: String, videoId: String, in label: UILabel) {
        label.yt6TitleVideoId = videoId
        guard !videoId.isEmpty else {
            label.text = title
            return
        }
        label.text = shared.titles[videoId] ?? title
        shared.request(videoId, listed: title) { [weak label] original in
            guard let label, label.yt6TitleVideoId == videoId, label.text != nil,
                  label.text != original else {
                return
            }
            label.text = original
            label.superview?.setNeedsLayout()
        }
    }

    /// Starts the lookups for a page that just arrived, before its rows
    /// are drawn. Any thread.
    static func prefetch(_ videos: [(id: String, title: String)]) {
        DispatchQueue.main.async {
            for video in videos.prefix(40) {
                shared.request(video.id, listed: video.title, then: nil)
            }
        }
    }

    private func request(_ id: String, listed: String, then done: ((String) -> Void)?) {
        if let known = titles[id] {
            done?(known)
            return
        }
        // Ids are 11 characters; anything else (a playlist, a stub) has no
        // oEmbed page.
        guard id.count == 11, !failed.contains(id) else {
            return
        }
        if let done {
            waiting[id, default: []].append(done)
        }
        guard inFlight.insert(id).inserted else {
            return
        }
        fetch(id) { [weak self] original in
            DispatchQueue.main.async {
                self?.finish(id, listed: listed, original: original)
            }
        }
    }

    private func finish(_ id: String, listed: String, original: String?) {
        inFlight.remove(id)
        let callbacks = waiting.removeValue(forKey: id) ?? []
        guard let original, !original.isEmpty else {
            failed.insert(id)
            return
        }
        remember(original, for: id)
        YT6LangProbe.noteOriginal(id, listed: listed, original: original)
        callbacks.forEach { $0(original) }
        scheduleSave()
    }

    private func remember(_ title: String, for id: String) {
        if titles.updateValue(title, forKey: id) == nil {
            order.append(id)
        }
        if order.count > Self.limit {
            let dropped = order.prefix(order.count - Self.limit)
            dropped.forEach { titles.removeValue(forKey: $0) }
            order.removeFirst(dropped.count)
        }
    }

    /// `GET /oembed`: 200 with `title`; 401/404 for private or removed
    /// videos — the listed title stays then.
    /// Not in the andCast-only and downloaded-only modes, which ask nothing
    /// of YouTube; their titles are the server's or the saved copy's.
    private func fetch(_ id: String, completion: @escaping (String?) -> Void) {
        guard !YT6Source.isLocal else {
            completion(nil)
            return
        }
        var components = URLComponents(string: "https://www.youtube.com/oembed")
        components?.queryItems = [
            URLQueryItem(name: "url", value: "https://www.youtube.com/watch?v=\(id)"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else {
            completion(nil)
            return
        }
        let task = session.dataTask(with: url) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let object = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            let title = (object as? [String: Any])?["title"] as? String
            completion(status == 200 ? title : nil)
        }
        task.resume()
    }

    /// One write a few seconds after a burst of answers.
    private func scheduleSave() {
        guard !saveScheduled else {
            return
        }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else {
                return
            }
            self.saveScheduled = false
            let pairs = self.order.compactMap { id in self.titles[id].map { [id, $0] } }
            AppCache.shared.diskQueue.async {
                AppCache.shared.writeDisk(pairs, key: Self.diskKey)
            }
        }
    }
}

private var yt6TitleVideoIdKey: UInt8 = 0

private extension UILabel {
    /// The video whose title this label shows — a reused row must not take
    /// the answer for the video it showed before.
    var yt6TitleVideoId: String? {
        get {
            objc_getAssociatedObject(self, &yt6TitleVideoIdKey) as? String
        }
        set {
            objc_setAssociatedObject(
                self, &yt6TitleVideoIdKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}
