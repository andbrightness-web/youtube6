import UIKit

/// Where the playing video comes from: «andCast», «YouTube» or «iPod»
/// (REQUEST723: «подставлять значок это с ютуба или это с нашего сервера»).
///
/// APPROXIMATION: 2.0.0 has no such element. A small label in the 2013
/// player-chrome manner — 10 pt bold white on a 50 % black rounded plate
/// with a faint white edge, like the overlay plates of iOS 6's player —
/// centered at the top of the controls, between the collapse button (left)
/// and the settings button (right), on the same line. It lives in the
/// controls layer, so it shows and hides with the controls.
final class YT6SourceBadge: UILabel {
    private static let badgeTag = 0x7A6C
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
        badge.font = UIFont.boldSystemFont(ofSize: 10)
        badge.textColor = .white
        badge.textAlignment = .center
        badge.backgroundColor = UIColor(white: 0, alpha: 0.5)
        badge.layer.cornerRadius = 3
        badge.layer.borderWidth = 1
        badge.layer.borderColor = UIColor(white: 1, alpha: 0.3).cgColor
        badge.clipsToBounds = true
        badge.isUserInteractionEnabled = false
        badge.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: player.settingsButton.centerYAnchor)
        ])
        return badge
    }
}
