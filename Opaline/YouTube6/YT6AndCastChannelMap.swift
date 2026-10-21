import Foundation

/// One channel, two names (REQUEST727: «каналы с YouTube и каналы мои, они
/// не сметчены»): the YouTube channel id (`UC…`) ↔ the andCast channel.
///
/// The catalog names the YouTube channel only when its `ChannelURL` is a
/// `/channel/UC…` address; most are `@handle` addresses (the server keeps
/// the UC id in `channel-profiles.json` but does not publish it — see the
/// report). The rest is learned on the iPod and kept: a YouTube row or
/// watch page of a video the server has gives its channel's UC id, and the
/// account's YouTube subscriptions match andCast channels by exact title.
enum YT6AndCastChannelMap {
    private static let key = "yt6.andcast.channelMap"
    private static let lock = NSLock()
    /// andCast channel id → YouTube channel id.
    private static var learned: [String: String] = {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }()

    /// The YouTube channel of an andCast channel, when known.
    static func youtubeId(of channel: YT6AndCastChannel) -> String? {
        if let own = channel.youtubeId {
            return own
        }
        lock.lock()
        defer { lock.unlock() }
        return learned[channel.id]
    }

    /// The andCast channel for an id of either kind.
    static func channel(_ id: String?) -> YT6AndCastChannel? {
        guard let id else {
            return nil
        }
        if let direct = YT6AndCastCatalog.shared.channel(id) {
            return direct
        }
        lock.lock()
        let match = learned.first { $0.value == id }?.key
        lock.unlock()
        return YT6AndCastCatalog.shared.channel(match)
    }

    /// A YouTube video row or page: its channel is the channel of the
    /// server's copy of that video.
    static func learn(videoId: String, youtubeChannel: String?) {
        guard let youtube = youtubeChannel, youtube.hasPrefix("UC"),
              let item = YT6AndCastCatalog.shared.item(videoId: videoId),
              let channel = YT6AndCastCatalog.shared.channel(item.channelId),
              channel.youtubeId == nil else {
            return
        }
        remember(channel.id, youtube, how: "video \(videoId)")
    }

    /// The account's YouTube subscriptions, matched by exact title.
    static func learn(subscriptions: [SubscribedChannel]) {
        var byTitle: [String: String] = [:]
        subscriptions.filter { $0.id.hasPrefix("UC") }.forEach { byTitle[fold($0.title)] = $0.id }
        for channel in YT6AndCastCatalog.shared.channels where youtubeId(of: channel) == nil {
            if let youtube = byTitle[fold(channel.title)] {
                remember(channel.id, youtube, how: "subscription title")
            }
        }
    }

    private static func fold(_ title: String) -> String {
        title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func remember(_ channel: String, _ youtube: String, how: String) {
        lock.lock()
        let known = learned[channel] == youtube
        if !known {
            learned[channel] = youtube
            UserDefaults.standard.set(learned, forKey: key)
        }
        lock.unlock()
        if !known {
            YT6AndCast.log("channels: \(channel) is YouTube \(youtube) (\(how))")
        }
    }
}
