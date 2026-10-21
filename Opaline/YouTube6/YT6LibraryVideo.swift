import Foundation

/// A catalog item as the app's `Video`: the server's artwork for the
/// thumbnail and the channel avatar, the catalog's title, channel, date and
/// length, the views of the server's stats base (`/v1/stats`).
enum YT6LibraryVideo {
    private static let clock: DateComponentsFormatter = {
        let format = DateComponentsFormatter()
        format.allowedUnits = [.hour, .minute, .second]
        format.zeroFormattingBehavior = .pad
        format.unitsStyle = .positional
        return format
    }()

    /// The rows format the date themselves (`VideoFormatters.formatRelativeDate`
    /// reads `yyyy-MM-dd'T'HH:mm:ssZ`).
    private static let iso: DateFormatter = {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
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
            viewCount: YT6AndCastNumbers.viewsText(YT6AndCastNumbers.shared.views(item: item.id)),
            publishedAt: item.date.map { iso.string(from: Date(timeIntervalSince1970: $0)) },
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
}
