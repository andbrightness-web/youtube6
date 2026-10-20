import UIKit

/// `YTPlaylistCell_iPhone`: a card — the thumbnail across the row, 114 pt
/// tall, 16 pt in (`layoutSubviews` @3d7b34/3d7baa); the title under it in
/// `largeLightFont` (15) `darkTextColor` (102), the video count under that in
/// `smallLightFont` (12) `mediumTextColor` (153) (`initWithReuseIdentifier:`
/// @3d76ee/3d7642); row height 4 + 114 + 4 + 52 = 174 (`+cellHeight`
/// @3d8074). The author line of 2.0.0 is left out: upstream's playlist model
/// has no owner.
final class YT6PlaylistCell: UITableViewCell {
    static let reuseId = "YT6PlaylistCell"
    static let height: CGFloat = 174
    private static let inset: CGFloat = 16
    private static let thumbnailHeight: CGFloat = 114

    private let plate = UIImageView(image: YT6.stretchableImage("grouped_table_card_middle"))
    private let thumb = ThumbnailImageView(frame: .zero)
    private let title = UILabel()
    private let count = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = YT6VideoRow.background
        backgroundView = plate
        thumb.contentMode = .scaleAspectFill
        thumb.clipsToBounds = true
        thumb.backgroundColor = UIColor(white: 0.85, alpha: 1)
        title.font = UIFont(name: "HelveticaNeue-Light", size: 15)
        title.textColor = UIColor(white: 102 / 255, alpha: 1)
        count.font = YT6.smallLightFont
        count.textColor = YT6.guideTitle
        [thumb, title, count].forEach(contentView.addSubview)
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
        (cell as? Self)?.configure(with: playlist)
        return cell
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = Self.inset
        let width = contentView.bounds.width - inset * 2
        thumb.frame = CGRect(x: inset, y: inset, width: width, height: Self.thumbnailHeight)
        title.frame = CGRect(x: inset, y: thumb.frame.maxY + 6, width: width, height: 20)
        count.frame = CGRect(x: inset, y: title.frame.maxY + 1, width: width, height: 16)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumb.cancel()
        thumb.image = nil
        title.text = nil
        count.text = nil
    }

    private func configure(with playlist: Playlist) {
        title.text = playlist.title
        count.text = playlist.itemCount.map { "common.videosCount".localized(with: $0) }
        if let string = playlist.thumbnailURL, let url = URL(string: string) {
            thumb.setImage(url: url)
        }
    }
}
