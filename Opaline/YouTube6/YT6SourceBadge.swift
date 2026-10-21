import UIKit

/// Where the playing video comes from: «andCast», «YouTube» or «iPod»
/// (REQUEST723: «подставлять значок это с ютуба или это с нашего сервера»).
///
/// APPROXIMATION: 2.0.0 has no such element. A small label in the 2013
/// player-chrome manner — 10 pt bold white on a 50 % black rounded plate
/// with a faint white edge, like the overlay plates of iOS 6's player —
/// centered at the top of the controls, between the collapse button (left)
/// and the settings button (right), on the same line. It lives in the
/// controls layer, so it shows and hides with the controls. Video rows
/// of videos the server has carry the same plate, smaller.
final class YT6SourceBadge: UILabel {
    private static let badgeTag = 0x7A6C
    private static let rowTag = 0x7A6D
    private static let padding: CGFloat = 6
    private static let height: CGFloat = 18

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + Self.padding * 2, height: Self.height)
    }

    /// From `PlaybackFacade.handlePrepared` once a source is attached.
    static func show(for source: VideoSource?, in context: PlaybackContext?) {
        guard let watch = context as? WatchViewController,
              let player = watch.videoPlayerView else {
            return
        }
        let badge = installed(in: player)
        let text = title(for: source)
        badge.text = text
        badge.invalidateIntrinsicContentSize()
        YT6AndCast.log("badge: \(text)")
    }

    /// A video row whose video the server has, in «YouTube + andCast»: the
    /// same plate, 9 pt, in the thumbnail's top-left corner (4 pt in, as
    /// the duration plate sits 4 pt from the opposite corner).
    static func markRow(_ thumbnail: UIView, videoId: String) {
        let has = YT6Source.mode == .youtubeAndCast
            && YT6AndCastCatalog.shared.item(videoId: videoId) != nil
        let mark = thumbnail.viewWithTag(rowTag) as? YT6SourceBadge
        guard has else {
            mark?.isHidden = true
            return
        }
        let shown = mark ?? rowMark(in: thumbnail)
        shown.isHidden = false
    }

    private static func rowMark(in thumbnail: UIView) -> YT6SourceBadge {
        let mark = YT6SourceBadge()
        mark.tag = rowTag
        style(mark, size: 9)
        mark.text = "andCast"
        mark.frame = CGRect(origin: CGPoint(x: 4, y: 4), size: mark.intrinsicContentSize)
        mark.frame.size.height = 14
        thumbnail.addSubview(mark)
        return mark
    }

    private static func style(_ badge: YT6SourceBadge, size: CGFloat) {
        badge.font = UIFont.boldSystemFont(ofSize: size)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = UIColor(white: 0, alpha: 0.5)
        badge.layer.cornerRadius = 3
        badge.layer.borderWidth = 1
        badge.layer.borderColor = UIColor(white: 1, alpha: 0.3).cgColor
        badge.clipsToBounds = true
        badge.isUserInteractionEnabled = false
    }

    private static func title(for source: VideoSource?) -> String {
        if let server = source as? YT6AndCastSource, server.playingFromServer {
            return "andCast"
        }
        if let saved = source as? DownloadedSource, !saved.isStreaming {
            return "iPod"
        }
        return "YouTube"
    }

    private static func installed(in player: VideoPlayerView) -> YT6SourceBadge {
        let host = player.controlsView
        if let badge = host.viewWithTag(badgeTag) as? YT6SourceBadge {
            return badge
        }
        let badge = YT6SourceBadge()
        badge.tag = badgeTag
        style(badge, size: 10)
        badge.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: player.settingsButton.centerYAnchor)
        ])
        return badge
    }
}
