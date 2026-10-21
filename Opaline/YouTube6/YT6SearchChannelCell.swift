import UIKit

/// A channel in the search results (Innertube `channelRenderer`).
struct YT6SearchChannel {
    let id: String
    let title: String
    let avatarURL: URL?
    /// The two count lines of the card; today's renderer swaps the fields
    /// around (subscribers in `videoCountText`) and puts the @handle in the
    /// other — handles are dropped, the rest shown as served.
    let lines: [String]
}

/// `YTChannelResultCell_iPhone` (`YTChannelCell_iPhone`): a card with the
/// channel picture 50×50 with a border, 12 pt in and centered vertically
/// (`layoutSubviews` @3cd994/3cd9d8, `+thumbnailSizeForEntry:` @3cdcb8);
/// 12 pt right of it, centered as a group, the title in `mediumLightFont`
/// and `XDarkTextColor` (#333) and the count lines in `smallLightFont` and
/// `mediumTextColor` (#999) (`initWithReuseIdentifier:` @3cd758/3cd808).
///
/// APPROXIMATION: 70 pt rows (`YTChannelCell +cellHeight` @3cdcb0; the result
/// cell's own height is computed from its fonts @3ce048, not read through);
/// the picture's border is a one-point light line; no subscribe switch.
final class YT6SearchChannelCell: UITableViewCell {
    static let reuseId = "YT6SearchChannelCell"
    static let height: CGFloat = 70
    private static let avatarSize: CGFloat = 50
    private static let inset: CGFloat = 12

    private let plate = UIImageView(image: YT6.stretchableImage("grouped_table_card_middle"))
    private let avatar = ThumbnailImageView(frame: .zero)
    private let title = UILabel()
    private let details = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = YT6VideoRow.background
        backgroundView = plate
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.backgroundColor = UIColor(white: 0.85, alpha: 1)
        avatar.layer.borderColor = UIColor(white: 0.8, alpha: 1).cgColor
        avatar.layer.borderWidth = 1
        title.font = YT6.mediumLightFont
        title.textColor = UIColor(white: 51 / 255, alpha: 1)
        details.font = YT6.smallLightFont
        details.textColor = YT6.guideTitle
        details.numberOfLines = 2
        [avatar, title, details].forEach(contentView.addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let size = Self.avatarSize
        avatar.frame = CGRect(
            x: Self.inset, y: ((bounds.height - size) / 2).rounded(), width: size, height: size
        )
        let left = avatar.frame.maxX + Self.inset
        let width = bounds.width - left - Self.inset
        let titleHeight = title.font.lineHeight.rounded(.up)
        let detailsHeight = details.sizeThatFits(CGSize(width: width, height: bounds.height)).height
        var y = ((bounds.height - titleHeight - detailsHeight) / 2).rounded()
        title.frame = CGRect(x: left, y: y, width: width, height: titleHeight)
        y += titleHeight
        details.frame = CGRect(x: left, y: y, width: width, height: detailsHeight)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        avatar.cancel()
        avatar.image = nil
    }

    func configure(with channel: YT6SearchChannel) {
        title.text = channel.title
        details.text = channel.lines.joined(separator: "\n")
        if let url = channel.avatarURL {
            avatar.setImage(url: url)
        }
        setNeedsLayout()
    }
}

extension InnertubeClient {
    /// A `channelRenderer` of the channel results.
    static func yt6SearchChannel(from item: [String: Any]) -> YT6SearchChannel? {
        guard let renderer = item["channelRenderer"] as? [String: Any],
              let id = renderer["channelId"] as? String
        else {
            return nil
        }
        let avatar = renderer.thumbnailURL().map { $0.hasPrefix("//") ? "https:" + $0 : $0 }
        let lines = ["videoCountText", "subscriberCountText"]
            .compactMap { renderer.innertubeText($0) }
            .filter { !$0.isEmpty && !$0.hasPrefix("@") }
        return YT6SearchChannel(
            id: id,
            title: renderer.innertubeText("title") ?? "",
            avatarURL: avatar.flatMap { URL(string: $0) },
            lines: lines
        )
    }

    /// A playlist of the playlist results: today's `lockupViewModel`, or the
    /// older `playlistRenderer`.
    static func yt6SearchPlaylist(from item: [String: Any]) -> Playlist? {
        if let lockup = item["lockupViewModel"] as? [String: Any] {
            guard lockup["contentType"] as? String == "LOCKUP_CONTENT_TYPE_PLAYLIST" else {
                return nil
            }
            return parseLockupPlaylist(lockup)
        }
        guard let renderer = item["playlistRenderer"] as? [String: Any],
              let id = renderer["playlistId"] as? String
        else {
            return nil
        }
        let thumbnails = (renderer["thumbnails"] as? [[String: Any]])?.first?["thumbnails"]
        return Playlist(
            id: id,
            title: renderer.innertubeText("title") ?? "",
            description: "",
            thumbnailURL: (thumbnails as? [[String: Any]]).flatMap { bestThumbnailURL(from: $0) },
            itemCount: (renderer["videoCount"] as? String).flatMap { Int($0) }
        )
    }
}
