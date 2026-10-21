import Foundation

/// The app's screens without YouTube (REQUEST724): in «andCast only» the
/// guide, What To Watch, My Subscriptions, channels, search, history and the
/// watch page come from the andCast catalog on the iPod and the server's own
/// shelves (`/v1/recommendations`, `/v1/history`,
/// `/v1/recommendations/next`, `/v1/items/{id}`), as the andCast client
/// shows them; in «Downloaded only» from the videos saved on the iPod.
/// `ServiceContainer` hands this object out instead of the Innertube
/// client in those modes, so the 2.0.0 screens stay what they are.
final class YT6Library {
    /// One list being paged: `yt6lib|<kind>|<offset>|<argument>`.
    private struct Cursor {
        static let prefix = "yt6lib|"
        let kind: String
        let offset: Int
        let argument: String

        var token: String { Self.prefix + "\(kind)|\(offset)|\(argument)" }

        init(kind: String, offset: Int, argument: String = "") {
            self.kind = kind
            self.offset = offset
            self.argument = argument
        }

        init?(_ token: String) {
            guard token.hasPrefix(Self.prefix) else {
                return nil
            }
            let parts = token.dropFirst(Self.prefix.count)
                .split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, let offset = Int(parts[1]) else {
                return nil
            }
            kind = String(parts[0])
            self.offset = offset
            argument = String(parts[2])
        }
    }

    static let shared = YT6Library()
    static let pageSize = 30

    private let lock = NSLock()
    private var converted: (revision: String, videos: [Video])?
    private var shelf: [String] = []

    private var stamp: String {
        (YT6AndCastCatalog.shared.revision ?? "") + "#" + YT6AndCastNumbers.shared.stamp
    }

    /// Every video of the current mode, newest first.
    var videos: [Video] {
        guard YT6Source.mode == .andCastOnly else {
            return DownloadStore.downloads().filter { DownloadStore.isDownloaded($0.id) }
        }
        let wanted = stamp
        lock.lock()
        let ready = converted
        lock.unlock()
        if let ready, ready.revision == wanted {
            return ready.videos
        }
        return convert(wanted)
    }

    /// What the other andCast clients list in Home and subscriptions: the
    /// videos of channels the owner did not exclude (`SubscriptionsVisible`).
    var followedVideos: [Video] {
        guard YT6Source.mode == .andCastOnly else {
            return videos
        }
        let hidden = Set(YT6AndCastCatalog.shared.channels.filter { !$0.visible }.map(\.id))
        return videos.filter { !hidden.contains($0.channelId ?? "") }
    }

    /// The guide's channel list: andCast's followed channels, as the iPhone,
    /// TV and Web clients list them (`subscriptionsVisible`).
    var channels: [SubscribedChannel] {
        guard YT6Source.mode == .andCastOnly else {
            var seen = Set<String>()
            return videos.compactMap { video in
                guard let id = video.channelId, seen.insert(id).inserted else {
                    return nil
                }
                return SubscribedChannel(
                    id: id, title: video.channelName, avatarURL: video.channelAvatarURL
                )
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        let filled = Set(YT6AndCastCatalog.shared.items.compactMap(\.channelId))
        let shown = YT6AndCastCatalog.shared.channels.filter {
            $0.visible && filled.contains($0.id)
        }
        return shown.map { channel in
            SubscribedChannel(
                id: channel.id,
                title: channel.title,
                avatarURL: YT6AndCast.artworkURL(channel.id, revision: channel.artwork)
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// What To Watch: the server's feed shelf for this time of day, then
    /// everything else newest first; offline the saved videos.
    private var homeList: [Video] {
        guard YT6Source.mode == .andCastOnly, !shelf.isEmpty else {
            return followedVideos
        }
        let picked = shelf.compactMap(video(item:))
        let ids = Set(picked.map(\.id))
        return picked + followedVideos.filter { !ids.contains($0.id) }
    }

    /// `recommend.py bucket_of`: weekday/weekend and night/morning/day/evening.
    private static func bucket(_ date: Date = Date()) -> String {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let part = hour >= 18 ? "evening" : hour >= 12 ? "day" : hour >= 6 ? "morning" : "night"
        return (calendar.isDateInWeekend(date) ? "weekend-" : "weekday-") + part
    }

    /// Off the main queue when the catalog or the numbers change: 14k rows
    /// built on the main queue held the screens (and their covers) back.
    func prepare() {
        guard YT6Source.mode == .andCastOnly else {
            return
        }
        let wanted = stamp
        DispatchQueue.global(qos: .utility).async { [weak self] in
            _ = self?.convert(wanted)
        }
    }

    private func convert(_ wanted: String) -> [Video] {
        let made = YT6AndCastCatalog.shared.items.map(YT6LibraryVideo.make)
        lock.lock()
        converted = (wanted, made)
        lock.unlock()
        return made
    }

    /// A channel's videos, by its andCast or its YouTube id.
    func videos(ofChannel id: String) -> [Video] {
        let own = YT6Source.mode == .andCastOnly ? YT6AndCastChannelMap.channel(id)?.id ?? id : id
        return videos.filter { $0.channelId == own }
    }

    func search(_ query: String) -> [Video] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else {
            return []
        }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return videos.filter { video in
            let text = video.title + " " + video.channelName
            return words.allSatisfy { text.range(of: $0, options: options) != nil }
        }
    }

    func video(item id: String) -> Video? {
        YT6AndCastCatalog.shared.item(andCastId: id).map(YT6LibraryVideo.make)
    }

    // MARK: Paging

    /// The page at `cursor` of the list it names.
    private func page(_ cursor: Cursor) -> FeedPage {
        let list: [Video]
        switch cursor.kind {
        case "home":
            list = homeList
        case "channel":
            list = videos(ofChannel: cursor.argument)
        case "search":
            list = search(cursor.argument)
        default:
            list = followedVideos
        }
        return slice(list, cursor)
    }

    private func slice(_ list: [Video], _ cursor: Cursor) -> FeedPage {
        let end = min(cursor.offset + Self.pageSize, list.count)
        let videos = cursor.offset < end ? Array(list[cursor.offset..<end]) : []
        let next = end < list.count
            ? Cursor(kind: cursor.kind, offset: end, argument: cursor.argument).token : nil
        if end < list.count {
            YT6AndCastArtwork.warm(Array(list[end..<min(end + Self.pageSize, list.count)]))
        }
        return FeedPage(videos: videos, continuation: next)
    }

    func firstPage(_ kind: String, argument: String = "") -> FeedPage {
        page(Cursor(kind: kind, offset: 0, argument: argument))
    }

    func nextPage(_ token: String) -> FeedPage {
        Cursor(token).map(page) ?? FeedPage(videos: [])
    }

    /// `/v1/recommendations`: `shelves["feed:<weekday|weekend>-<part>"]`,
    /// the andCast client's Home.
    func loadShelf(_ completion: @escaping () -> Void) {
        guard YT6Source.mode == .andCastOnly else {
            completion()
            return
        }
        let tz = TimeZone.current.secondsFromGMT() / 60
        YT6AndCast.call("v1/recommendations", query: ["tz": "\(tz)"]) { [weak self] body in
            let shelves = body?["shelves"] as? [String: Any] ?? [:]
            let wanted = shelves["feed:" + Self.bucket()] ?? shelves["new"]
            let entries = wanted as? [[String: Any]] ?? []
            self?.shelf = entries.compactMap { $0["id"] as? String }
            YT6AndCast.log("library: home shelf \(self?.shelf.count ?? 0) videos")
            completion()
        }
    }
}
