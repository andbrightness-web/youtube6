import Foundation

/// One video of the andCast catalog as the iPod keeps it (short JSON keys:
/// the file holds ~25k of them).
struct YT6AndCastItem: Codable {
    enum CodingKeys: String, CodingKey {
        case id = "i", youtubeId = "y", title = "n", channelId = "c"
        case date = "d", seconds = "r", artwork = "a"
    }

    let id: String
    let youtubeId: String
    let title: String
    let channelId: String?
    let date: Double?
    let seconds: Double?
    let artwork: String?

    /// The id the app knows this video by: YouTube's, or a stand-in for
    /// the few files the server has no YouTube id for.
    var videoId: String { youtubeId.isEmpty ? "ac_" + id : youtubeId }
}

/// A channel of the catalog. `visible` is the server's
/// `SubscriptionsVisible`: false for the channels the owner excluded (the
/// music download roots of `library-rules.json`); every andCast client
/// leaves them out of subscriptions, Home and recommendations.
struct YT6AndCastChannel: Codable {
    enum CodingKeys: String, CodingKey {
        case id = "i", title = "n", artwork = "a", youtubeId = "y"
        case visible = "v", overview = "o", url = "u"
    }

    let id: String
    let title: String
    let artwork: String?
    let youtubeId: String?
    let visible: Bool
    let overview: String?
    let url: String?
}

/// A playlist of the catalog (`playlists`: the source's playlists and the
/// server's per-channel lists), members by andCast item id.
struct YT6AndCastPlaylist: Codable {
    enum CodingKeys: String, CodingKey {
        case id = "i", title = "n", items = "m", channelId = "c"
    }

    let id: String
    let title: String
    let items: [String]
    let channelId: String?
}

struct YT6AndCastStore: Codable {
    /// The layout of this file; an older one is read again from scratch.
    static let currentVersion = 3

    var version: Int?
    var account: String
    var revision: String
    var items: [YT6AndCastItem]
    var channels: [YT6AndCastChannel]
    var playlists: [YT6AndCastPlaylist]?
}
