import UIKit

/// `YTPlaylistCell_iPhone`: a card — the thumbnail across the row, 114 pt
/// tall, 16 pt in (`layoutSubviews` @3d7b34/3d7baa); the title under it in
/// `largeLightFont` (15) `darkTextColor` (102), the video count under that in
/// `smallLightFont` (12) `mediumTextColor` (153) (`initWithReuseIdentifier:`
/// @3d76ee/3d7642); row height 4 + 114 + 4 + 52 = 174 (`+cellHeight`
/// @3d8074). The author line of 2.0.0 is left out: upstream's playlist model
/// has no owner.
final class YT6PlaylistCard: UIView {
    static let height: CGFloat = 174
    private static let inset: CGFloat = 16
    private static let thumbnailHeight: CGFloat = 114

    private let plate = UIImageView(image: YT6.stretchableImage("grouped_table_card_middle"))
    private let thumb = ThumbnailImageView(frame: .zero)
    private let title = UILabel()
    private let count = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = YT6VideoRow.background
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.backgroundColor = UIColor(white: 0.85, alpha: 1)
        title.font = UIFont(name: "HelveticaNeue-Light", size: 15)
        title.textColor = UIColor(white: 102 / 255, alpha: 1)
        count.font = YT6.smallLightFont
        count.textColor = YT6.guideTitle
        [plate, thumb, title, count].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        plate.frame = bounds
        let inset = Self.inset
        let width = bounds.width - inset * 2
        thumb.frame = CGRect(x: inset, y: inset, width: width, height: Self.thumbnailHeight)
        title.frame = CGRect(x: inset, y: thumb.frame.maxY + 6, width: width, height: 20)
        count.frame = CGRect(x: inset, y: title.frame.maxY + 1, width: width, height: 16)
    }

    func configure(with playlist: Playlist) {
        title.text = playlist.title
        count.text = playlist.itemCount.map { "common.videosCount".localized(with: $0) }
        if let string = playlist.thumbnailURL, let url = URL(string: string) {
            thumb.setImage(url: url)
        }
    }

    func clear() {
        thumb.cancel()
        thumb.image = nil
        title.text = nil
        count.text = nil
    }
}

/// The card as a table row (Playlists).
final class YT6PlaylistCell: UITableViewCell {
    static let reuseId = "YT6PlaylistCell"
    static let height = YT6PlaylistCard.height

    private let card = YT6PlaylistCard()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = YT6VideoRow.background
        card.frame = contentView.bounds
        card.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(card)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func dequeue(
        from tableView: UITableView,
        at indexPath: IndexPath,
        with playlist: Playlist
    ) -> UITableViewCell {
        tableView.register(Self.self, forCellReuseIdentifier: reuseId)
        let cell = tableView.dequeueReusableCell(withIdentifier: reuseId, for: indexPath)
        (cell as? Self)?.card.configure(with: playlist)
        return cell
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        card.clear()
    }
}

/// The card as a collection item (a channel's Playlists tab).
final class YT6PlaylistItemCell: UICollectionViewCell {
    static let reuseId = "YT6PlaylistItemCell"

    let card = YT6PlaylistCard()

    override init(frame: CGRect) {
        super.init(frame: frame)
        card.frame = contentView.bounds
        card.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(card)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        card.clear()
    }
}
