import UIKit

/// A row of the open playlist panel: `YTVideoCell_iPhone` in context 1
/// (`-[YTVideoListFeedTableSectionController cellForRow:]` @17ed8 →
/// `setContext:` @3df804, `setPlaylistPosition:` @3df7a0 «%i»), dark plates
/// (`cellBackgroundStyle` 1, `updateBackground` @3df8f4), the title in
/// `lightTextColor` (#CCCCCC). `layoutSubviews` @3df14c: the position
/// label 32 pt wide at the left edge, the 123×70 thumbnail right after it,
/// `video_playing_arrow` 16 pt in on the playing row.
final class YT6VideoListCell: UITableViewCell {
    static let reuseId = "YT6VideoListCell"
    private static let positionWidth: CGFloat = 32
    private static let cardInset: CGFloat = 8

    var onMenuTap: ((UIView) -> Void)?

    private let plate = UIImageView()
    private let number = UILabel()
    private let arrow = UIImageView(image: YT6.image("video_playing_arrow"))
    private let thumbnail = ThumbnailImageView(frame: .zero)
    private let title = UILabel()
    private let uploader = UILabel()
    private let menu = UIButton(type: .custom)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.backgroundColor = UIColor(white: 0.2, alpha: 1)
        // APPROXIMATION: the position label's font is not read; 12 pt Light.
        number.font = YT6.smallLightFont
        number.textColor = YT6.Watch.medium
        number.textAlignment = .center
        title.font = YT6.mediumLightFont
        title.textColor = UIColor(white: 204 / 255, alpha: 1)
        title.numberOfLines = 2
        uploader.font = YT6.smallLightFont
        uploader.textColor = YT6.Watch.medium
        menu.setTitle("⋮", for: .normal)
        menu.setTitleColor(YT6.Watch.medium, for: .normal)
        menu.addTarget(self, action: #selector(tapMenu), for: .touchUpInside)
        [plate, number, arrow, thumbnail, title, uploader, menu].forEach(contentView.addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// `setPositionForRow:rowsInSection:` @3dd9c4.
    static func position(of row: Int, in count: Int) -> Int {
        if count == 1 {
            return 3
        }
        if row == 0 {
            return 0
        }
        return row == count - 1 ? 2 : 1
    }

    /// `number` is the 1-based place, `nil` on the playing row.
    func configure(_ video: Video, number place: Int?, position: Int) {
        number.text = place.map(String.init)
        number.isHidden = place == nil
        arrow.isHidden = place != nil
        title.text = video.title
        uploader.text = video.channelName
        // APPROXIMATION: the dark plate per position follows the light
        // mapping of @404bf4 (top / middle / bottom / single).
        let names = ["top", "middle", "bottom", "single"]
        plate.image = YT6.stretchableImage("grouped_table_card_\(names[position])_dark")
        thumbnail.maxPixelSize = ThumbnailSizing.pixelSize(
            forDisplayWidth: YT6VideoRow.thumbnailSize.width,
            scale: UIScreen.main.scale
        )
        if let url = URL(string: video.thumbnailURL) {
            thumbnail.setImage(url: url, videoId: video.isShort ? nil : video.id)
        }
        setNeedsLayout()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thumbnail.cancel()
        thumbnail.image = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = Self.cardInset
        let card = contentView.bounds.insetBy(dx: inset, dy: 0)
        let out = YT6.Watch.plateOutset
        plate.frame = card.insetBy(dx: -out, dy: -out)
        number.frame = CGRect(x: card.minX, y: 0, width: Self.positionWidth, height: card.height)
        arrow.sizeToFit()
        arrow.center = CGPoint(x: card.minX + 16 + arrow.bounds.width / 2, y: card.midY)
        let size = YT6VideoRow.thumbnailSize
        thumbnail.frame = CGRect(
            x: card.minX + Self.positionWidth,
            y: ((card.height - size.height) / 2).rounded(),
            width: size.width,
            height: size.height
        )
        menu.frame = CGRect(x: card.maxX - 28, y: 0, width: 28, height: 36)
        layoutText(in: card)
    }

    private func layoutText(in card: CGRect) {
        let left = thumbnail.frame.maxX + YT6VideoRow.textGap
        let width = card.maxX - left - YT6VideoRow.textRight
        let fit = CGSize(width: width, height: .greatestFiniteMagnitude)
        title.frame.size = title.sizeThatFits(fit)
        title.frame.size.width = width
        uploader.frame.size = CGSize(width: width, height: uploader.font.lineHeight.rounded(.up))
        let total = title.frame.height + uploader.frame.height
        title.frame.origin = CGPoint(x: left, y: ((card.height - total) / 2).rounded())
        uploader.frame.origin = CGPoint(x: left, y: title.frame.maxY)
    }

    @objc
    private func tapMenu() {
        onMenuTap?(menu)
    }
}
