import Foundation

/// `[Lang]` lines in opaline.log for the signed-in case, which cannot be
/// measured from srv (REQUEST719): per list kind, once per launch, the
/// title-like fields of the first three videos of the RESPONSE as it came
/// (title, headline, accessibility labels, anything named original /
/// localized / language), and every list title oEmbed corrected.
///
/// Response bodies only — never request headers, cookies, tokens or the
/// account's own data: only renderers that carry a video id, and the page's
/// `videoDetails` / microformat / primary info, are read.
enum YT6LangProbe {
    /// A renderer (or title holder) of the response, by its key.
    private struct Holder {
        let key: String
        let id: String
        let node: [String: Any]
    }

    /// Requests whose answer is a list of videos (or a video's own page).
    private static let kinds: Set<String> = [
        "browse", "browseAnon", "webBrowse", "tvHistory", "playlistVideos",
        "channelTab", "channelTabNext", "channelBrowse", "channelSearch",
        "channelSearchNext", "queuePage", "watchNext", "directPlayback"
    ]
    /// Holders of the watched video's own title.
    private static let pageHolders: Set<String> = [
        "videoDetails", "playerMicroformatRenderer", "videoPrimaryInfoRenderer",
        "videoMetadataRenderer", "slimVideoMetadataSectionRenderer"
    ]
    private static let lock = NSLock()
    private static var seen: Set<String> = []
    private static var corrected = 0
    private static var compared = 0

    /// From `InnertubeRequestExecutor` on every parsed answer; any thread.
    static func received(_ json: [String: Any], parsed: Any, tag: String) {
        YT6OriginalTitles.prefetch(videos(in: parsed).map { (id: $0.id, title: $0.title) })
        let name = String(tag.prefix { $0 != "(" })
        guard kinds.contains(name) else {
            return
        }
        // Home, subscriptions and the categories are all `browse(<id>)`.
        let kind = name.hasPrefix("browse") ? tag : name
        lock.lock()
        let first = seen.insert(kind).inserted
        lock.unlock()
        guard first else {
            return
        }
        var found: [Holder] = []
        collect(json, key: "", into: &found, depth: 0)
        AppLog.log("Lang", "\(kind): \(found.count) holders")
        for holder in found {
            let fields = titleFields(holder.node, path: "", depth: 0).prefix(10)
            let text = fields.map { "\($0.0)=«\($0.1)»" }.joined(separator: " ")
            AppLog.log("Lang", "\(kind) \(holder.key) \(holder.id): \(text)")
        }
    }

    /// Main thread: a list title next to the uploaded one.
    static func noteOriginal(_ id: String, listed: String, original: String) {
        compared += 1
        let differs = listed != original && !listed.isEmpty
        if differs {
            corrected += 1
        }
        guard compared <= 3 || (differs && corrected <= 25) else {
            return
        }
        let verdict = differs ? "translated" : "same"
        AppLog.log("Lang", "oembed \(id) \(verdict): list=«\(listed)» original=«\(original)»")
    }

    private static func videos(in parsed: Any) -> [Video] {
        switch parsed {
        case let page as FeedPage:
            return page.videos
        case let page as WatchPage:
            return [page.video] + page.relatedVideos + (page.playlistVideos ?? [])
        case let page as SearchPage:
            return page.videos
        case let list as [Video]:
            return list
        default:
            return []
        }
    }

    /// The first three renderers that carry a video id themselves, plus the
    /// page's own title holders.
    private static func collect(
        _ node: Any, key: String, into found: inout [Holder], depth: Int
    ) {
        guard depth < 48 else {
            return
        }
        if let list = node as? [Any] {
            for item in list {
                collect(item, key: key, into: &found, depth: depth + 1)
            }
            return
        }
        guard let dict = node as? [String: Any] else {
            return
        }
        let id = (dict["videoId"] as? String) ?? (dict["contentId"] as? String)
        let isRenderer = key.hasSuffix("Renderer") || key.hasSuffix("ViewModel")
        if pageHolders.contains(key) {
            found.append(Holder(key: key, id: id ?? "-", node: dict))
            return
        }
        let videos = found.filter { !pageHolders.contains($0.key) }
        if isRenderer, let id, id.count == 11 {
            if videos.count < 3, !videos.contains(where: { $0.id == id }) {
                found.append(Holder(key: key, id: id, node: dict))
            }
            return
        }
        for (child, value) in dict {
            collect(value, key: child, into: &found, depth: depth + 1)
        }
    }

    /// Strings under keys that name a title or a language; menus, endpoints
    /// and artwork skipped.
    private static func titleFields(_ node: Any, path: String, depth: Int) -> [(String, String)] {
        guard depth < 12 else {
            return []
        }
        if let text = node as? String {
            let lower = path.lowercased()
            let named = ["title", "headline", "label", "original", "locali", "lang"]
            guard named.contains(where: { lower.contains($0) }) else {
                return []
            }
            let short = path.split(separator: ".").suffix(3).joined(separator: ".")
            return [(short, String(text.prefix(100)))]
        }
        if let list = node as? [Any] {
            return list.prefix(4).flatMap { titleFields($0, path: path, depth: depth + 1) }
        }
        guard let dict = node as? [String: Any] else {
            return []
        }
        let skipped = ["menu", "endpoint", "command", "thumbnail", "overlay", "tracking", "url"]
        return dict.keys.sorted().flatMap { key -> [(String, String)] in
            let lower = key.lowercased()
            guard !skipped.contains(where: { lower.contains($0) }), let value = dict[key] else {
                return []
            }
            return titleFields(value, path: path + "." + key, depth: depth + 1)
        }
    }
}
