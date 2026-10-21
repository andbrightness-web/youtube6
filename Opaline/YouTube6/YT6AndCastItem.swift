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

struct YT6AndCastChannel: Codable {
    enum CodingKeys: String, CodingKey {
        case id = "i", title = "n", artwork = "a", youtubeId = "y"
    }

    let id: String
    let title: String
    let artwork: String?
    let youtubeId: String?
}

struct YT6AndCastStore: Codable {
    var account: String
    var revision: String
    var items: [YT6AndCastItem]
    var channels: [YT6AndCastChannel]
}
