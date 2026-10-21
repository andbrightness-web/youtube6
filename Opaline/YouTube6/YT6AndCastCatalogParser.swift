import Foundation

/// Turns a `/v1/catalog` answer (whole or delta) into the compact store.
///
/// Fields as the server writes them (`server/core.py` `snapshot`): `Id`,
/// `Name`, `Type`, `IsFolder`, `PremiereDate`/`DateCreated`,
/// `RunTimeTicks`, `ArtworkRevision`, `ChannelId`, `ParentId` and
/// `YouTubeId` (from the video's `.info.json`, ffprobe `purl` or its
/// `[id]` file name); channels with `Id`, `Name`, `ArtworkRevision`,
/// `ChannelURL`.
enum YT6AndCastCatalogParser {
    typealias Store = YT6AndCastCatalog.Store
    typealias Item = YT6AndCastCatalog.Item
    typealias Channel = YT6AndCastCatalog.Channel

    private static let dateFormat: DateFormatter = {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return format
    }()

    static func store(from data: Data, previous: Store?, account: String) -> Store? {
        guard let body = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let revision = body["revision"] as? String else {
            return nil
        }
        let rawItems = body["items"] as? [[String: Any]] ?? []
        let channels = (body["channels"] as? [[String: Any]] ?? []).compactMap(channel)
        let folders = Set(channels.map(\.id))
        let changed = rawItems.compactMap { item($0, channels: folders) }
        var items: [Item]
        if body["delta"] as? Bool == true {
            guard let previous, previous.revision == body["base"] as? String else {
                return nil
            }
            let removed = Set(body["removed"] as? [String] ?? [])
            let replaced = Set(rawItems.compactMap { $0["Id"] as? String })
            items = previous.items.filter { !removed.contains($0.id) && !replaced.contains($0.id) }
            items += changed
        } else {
            items = changed
        }
        items.sort { ($0.date ?? 0) > ($1.date ?? 0) }
        return Store(account: account, revision: revision, items: items, channels: channels)
    }

    private static func item(_ raw: [String: Any], channels: Set<String>) -> Item? {
        guard raw["IsFolder"] as? Bool != true,
              let id = raw["Id"] as? String,
              let title = raw["Name"] as? String else {
            return nil
        }
        let parent = raw["ParentId"] as? String
        let folder = parent.flatMap { channels.contains($0) ? $0 : nil }
        let channel = raw["ChannelId"] as? String ?? folder
        let ticks = raw["RunTimeTicks"] as? Double
        return Item(
            id: id,
            youtubeId: raw["YouTubeId"] as? String ?? "",
            title: title,
            channelId: channel,
            date: date(raw["PremiereDate"]) ?? date(raw["DateCreated"]),
            seconds: ticks.map { $0 / 10_000_000 },
            artwork: raw["ArtworkRevision"] as? String
        )
    }

    private static func channel(_ raw: [String: Any]) -> Channel? {
        guard let id = raw["Id"] as? String, let title = raw["Name"] as? String else {
            return nil
        }
        return Channel(
            id: id,
            title: title,
            artwork: raw["ArtworkRevision"] as? String,
            youtubeId: youtubeChannel(raw["ChannelURL"] as? String)
        )
    }

    /// `https://www.youtube.com/channel/UC…` → `UC…`; handles are not ids.
    private static func youtubeChannel(_ url: String?) -> String? {
        guard let url, let parts = URL(string: url)?.pathComponents,
              let index = parts.firstIndex(of: "channel"), index + 1 < parts.count,
              parts[index + 1].hasPrefix("UC") else {
            return nil
        }
        return parts[index + 1]
    }

    /// Jellyfin writes seven fractional digits; only the seconds count.
    private static func date(_ value: Any?) -> Double? {
        guard let text = value as? String, text.count >= 19 else {
            return nil
        }
        return dateFormat.date(from: String(text.prefix(19)))?.timeIntervalSince1970
    }
}
