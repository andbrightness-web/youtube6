import Foundation

/// A catalog item as the app's `Video`: the server's artwork for the
/// thumbnail and the channel avatar, the catalog's title, channel, date and
/// length. andCast keeps no view counts in the catalog.
enum YT6LibraryVideo {
    private static let clock: DateComponentsFormatter = {
        let format = DateComponentsFormatter()
        format.allowedUnits = [.hour, .minute, .second]
        format.zeroFormattingBehavior = .pad
        format.unitsStyle = .positional
        return format
    }()

    private static let age: DateComponentsFormatter = {
        let format = DateComponentsFormatter()
        format.allowedUnits = [.year, .month, .weekOfMonth, .day, .hour, .minute]
        format.maximumUnitCount = 1
        format.unitsStyle = .full
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        format.calendar = calendar
        return format
    }()

    static func make(_ item: YT6AndCastCatalog.Item) -> Video {
        let channel = YT6AndCastCatalog.shared.channel(item.channelId)
        let avatar = channel.flatMap { YT6AndCast.artworkURL($0.id, revision: $0.artwork) }
        return Video(
            id: item.videoId,
            title: item.title,
            channelId: channel?.id ?? item.channelId,
            channelName: channel?.title ?? "",
            channelAvatarURL: avatar,
            thumbnailURL: YT6AndCast.artworkURL(item.id, revision: item.artwork) ?? "",
            viewCount: nil,
            publishedAt: published(item.date),
            duration: duration(item.seconds)
        )
    }

    /// "4:07", "1:02:33" — YouTube's length text.
    static func duration(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else {
            return nil
        }
        var text = clock.string(from: seconds.rounded()) ?? ""
        if seconds < 3_600, text.hasPrefix("0:") {
            text.removeFirst(2)
        }
        while text.hasPrefix("0"), text.count > 4 {
            text.removeFirst()
        }
        return text
    }

    /// "3 weeks ago".
    static func published(_ date: Double?) -> String? {
        guard let date else {
            return nil
        }
        let seconds = Date().timeIntervalSince1970 - date
        guard seconds > 60, let text = age.string(from: seconds) else {
            return nil
        }
        return text + " ago"
    }
}
