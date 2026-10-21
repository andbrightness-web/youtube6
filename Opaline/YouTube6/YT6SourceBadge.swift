import AVFoundation
import UIKit

/// Where a video comes from: «YouTube», «andCast» or «iPod» (REQUEST723,
/// 727, 730: «не обманывал меня»).
///
/// The player's plate is read off what actually plays — the current
/// `AVPlayerItem`'s asset: a file URL is the saved copy, an andCast address
/// (direct stream or HLS) is the server, anything else (googlevideo, the
/// local SABR/HLS proxy, a composition of YouTube tracks) is YouTube. It
/// follows the player's `currentItem`, so a fallback mid-play, a rebuild,
/// a quality switch or the next video change it, each change logged.
///
/// APPROXIMATION: 2.0.0 has no such element. In the player: 10 pt bold
/// white on a 50 % black rounded plate with a faint white edge, centered at
/// the top of the controls between the collapse and settings buttons, shown
/// and hidden with the controls. On every video thumbnail: the same plate,
/// 9 pt, in the bottom-left corner, opposite the duration plate (4 pt in);
/// andCast's plate in 2.0.0's link blue so the two read apart at a glance.
final class YT6SourceBadge: UILabel {
    enum Source: String {
        case youtube = "YouTube"
        case andCast = "andCast"
        case iPod = "iPod"
    }

    private static let badgeTag = 0x7A6C
    private static let rowTag = 0x7A6D
    private static let padding: CGFloat = 6
    private static let height: CGFloat = 18
    private static let rowHeight: CGFloat = 14
    /// `YT6.Watch` link blue #1B7FCC.
    private static let andCastColor = UIColor(
        red: 27 / 255, green: 127 / 255, blue: 204 / 255, alpha: 0.9
    )

    private var watching: NSKeyValueObservation?
    private weak var player: AVPlayer?
    private var shown: Source?

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + Self.padding * 2, height: Self.height)
    }

    // MARK: Player

    /// From `attachPlayer`: watch this player's item from now on.
    static func follow(_ player: AVPlayer, in view: VideoPlayerView) {
        let badge = installed(in: view)
        guard badge.player !== player else {
            badge.update(player.currentItem, why: "same player")
            return
        }
        badge.player = player
        let options: NSKeyValueObservingOptions = [.initial, .new]
        badge.watching = player.observe(\.currentItem, options: options) { [weak badge] player, _ in
            DispatchQueue.main.async {
                badge?.update(player.currentItem, why: "item")
            }
        }
    }

    /// From `PlaybackFacade.handlePrepared`: the item just attached.
    static func show(for source: VideoSource?, in context: PlaybackContext?) {
        guard let watch = context as? WatchViewController,
              let view = watch.videoPlayerView, let player = view.player else {
            return
        }
        follow(player, in: view)
    }

    /// What the item really plays from; never the URL itself in the log.
    static func source(of item: AVPlayerItem) -> (Source, String) {
        guard let url = (item.asset as? AVURLAsset)?.url else {
            return (.youtube, "composed YouTube tracks")
        }
        if url.isFileURL {
            return (.iPod, "saved file")
        }
        let host = url.host?.lowercased() ?? ""
        if YT6AndCast.isOwnHost(host) || host == YT6AndCastReach.base?.host?.lowercased() {
            return (.andCast, url.path.contains("/hls") || url.pathExtension == "m3u8"
                ? "andCast HLS" : "andCast stream")
        }
        if host == "127.0.0.1" || host == "localhost" {
            return (.youtube, "local YouTube proxy")
        }
        let how = host.hasSuffix("googlevideo.com") ? "googlevideo" : "YouTube \(url.scheme ?? "")"
        return (.youtube, how)
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

    // MARK: Thumbnails

    /// Where this video would play from if opened now: the saved copy, the
    /// server (when the mode plays from it and it answers), else YouTube.
    static func expected(for videoId: String) -> Source {
        if DownloadStore.isDownloaded(videoId) {
            return .iPod
        }
        guard YT6AndCastCatalog.shared.item(videoId: videoId) != nil, YT6AndCast.isSignedIn else {
            return .youtube
        }
        switch YT6Source.mode {
        case .andCastOnly:
            return .andCast
        case .youtubeAndCast:
            return YT6AndCastReach.base != nil ? .andCast : .youtube
        case .downloadedOnly:
            return .youtube
        }
    }

    /// The plate in a thumbnail's bottom-left corner, on every row.
    static func markRow(_ thumbnail: UIView, videoId: String) {
        let source = expected(for: videoId)
        let mark = thumbnail.viewWithTag(rowTag) as? YT6SourceBadge ?? rowMark(in: thumbnail)
        mark.text = source.rawValue
        mark.backgroundColor = source == .andCast ? andCastColor : UIColor(white: 0, alpha: 0.6)
        mark.isHidden = videoId.isEmpty
    }

    private static func rowMark(in thumbnail: UIView) -> YT6SourceBadge {
        let mark = YT6SourceBadge()
        mark.tag = rowTag
        style(mark, size: 9)
        mark.translatesAutoresizingMaskIntoConstraints = false
        thumbnail.addSubview(mark)
        NSLayoutConstraint.activate([
            mark.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor, constant: 4),
            mark.bottomAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: -4),
            mark.heightAnchor.constraint(equalToConstant: rowHeight)
        ])
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

    private func update(_ item: AVPlayerItem?, why: String) {
        guard let item else {
            return
        }
        let (source, how) = Self.source(of: item)
        text = source.rawValue
        backgroundColor = source == .andCast ? Self.andCastColor : UIColor(white: 0, alpha: 0.5)
        invalidateIntrinsicContentSize()
        if source != shown {
            YT6AndCast.log("badge: \(source.rawValue) (\(how), \(why))")
            shown = source
        }
    }
}
