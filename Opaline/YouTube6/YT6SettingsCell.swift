import UIKit

/// A settings card row — `YTSettingsCell`, `YTCardButtonCell` and
/// `YTUserAccountCell` on their shared base `YTTableViewCell`.
///
/// `-[YTTableViewCell layoutSubviews]` @3dd57c: the content view is the cell
/// inset 8 pt left and right (`marginLeft`/`marginRight` @3dda7c) and by
/// `marginTop`/`marginBottom`; the card image lies under it 3 pt larger on
/// every side (@3dd7ae, @3dd802). Text is `mediumLightFont` (13) in
/// `darkTextColor` (`initWithReuseIdentifier:` @3dceca, @3dcf5e), the title
/// 12 pt from the left and the value 12 pt from the right, the checkmark
/// flush right (`layoutSubviews` @3dd0d8, @3dd12c, @3dd16a).
final class YT6SettingsCell: UITableViewCell {
    /// `-[YTTableViewCell setPositionForRow:rowsInSection:]` @3dd9c4.
    enum Position: Int {
        case top = 0
        case middle = 1
        case bottom = 2
        case single = 3

        /// `+[YTUIResources groupedTableBackgroundImageWithPosition:
        /// separatorStyle:selected:]` @404bf4 (jump table @404c06); the
        /// highlighted card adds `_selected` (`imageNamed:stretchable:selected:`).
        var card: String {
            switch self {
            case .top:
                return "grouped_table_card_top"
            case .middle:
                return "grouped_table_card_middle"
            case .bottom:
                return "grouped_table_card_bottom"
            case .single:
                return "grouped_table_card"
            }
        }

        init(row: Int, of count: Int) {
            if count == 1 {
                self = .single
            } else if row == 0 {
                self = .top
            } else {
                self = row == count - 1 ? .bottom : .middle
            }
        }
    }

    private static let padding: CGFloat = 12
    /// `-[YTCardButtonCell initWithReuseIdentifier:]` @3cb924 and
    /// `-[YTUserAccountCell initWithReuseIdentifier:]` @788be; the settings
    /// cell takes the same 4 pt at the top of a section and at its bottom
    /// (`-[YTSettingsCell setPosition:]` @3dd3aa, @3dd3d8).
    private static let margin: CGFloat = 4
    /// `-[YTUserAccountCell layoutSubviews]` @78948: 32 pt avatar 10 pt in.
    private static let avatarSize: CGFloat = 32
    private static let avatarLeft: CGFloat = 10
    /// APPROXIMATION: the category color square has no 2.0.0 analog.
    private static let swatchSize: CGFloat = 12

    private let card = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let checkmark = UIImageView(
        image: YT6.image("checkmark"),
        highlightedImage: YT6.image("checkmark_selected")
    )
    private let swatch = UIView()
    private let avatar = UIImageView()
    private var kind = YT6SettingsRow.Kind.value
    private var marginTop: CGFloat = 0
    private var marginBottom: CGFloat = 0

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        clipsToBounds = false
        contentView.clipsToBounds = false
        contentView.addSubview(card)
        for label in [titleLabel, detailLabel] {
            label.font = YT6.mediumLightFont
            label.textColor = YT6SettingsStyle.darkText
            label.highlightedTextColor = YT6SettingsStyle.darkText
            label.backgroundColor = .clear
            contentView.addSubview(label)
        }
        avatar.contentMode = .scaleAspectFill
        avatar.clipsToBounds = true
        avatar.backgroundColor = UIColor(white: 0.85, alpha: 1)
        for view in [checkmark, swatch, avatar] {
            contentView.addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func height(of kind: YT6SettingsRow.Kind) -> CGFloat {
        switch kind {
        case .value:
            return YT6SettingsStyle.rowHeight
        case .button:
            return YT6SettingsStyle.buttonHeight
        case .account:
            return YT6SettingsStyle.accountHeight
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.frame = CGRect(
            x: 8,
            y: marginTop,
            width: bounds.width - 16,
            height: bounds.height - marginTop - marginBottom
        )
        card.frame = contentView.bounds.insetBy(dx: -3, dy: -3)
        layoutContent(in: contentView.bounds)
    }

    func configure(_ row: YT6SettingsRow, position: Position) {
        kind = row.kind
        card.image = YT6.stretchableImage(position.card)
        card.highlightedImage = YT6.stretchableImage(position.card + "_selected")
        titleLabel.text = row.title
        detailLabel.text = row.checked ? nil : row.detail
        checkmark.isHidden = !row.checked
        swatch.isHidden = row.swatch == nil
        swatch.backgroundColor = row.swatch
        avatar.isHidden = row.kind != .account
        avatar.image = row.image
        configureKind(row, position: position)
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        // `-[YTSettingsCell setHighlighted:animated:]` @3dd220: only the card
        // changes, to its `_selected` image.
        card.isHighlighted = highlighted
        checkmark.isHighlighted = highlighted
    }

    private func configureKind(_ row: YT6SettingsRow, position: Position) {
        switch row.kind {
        case .value:
            marginTop = position == .top ? Self.margin : 0
            marginBottom = position == .bottom ? Self.margin : 0
            titleLabel.textColor = row.textColor ?? YT6SettingsStyle.darkText
        case .button:
            marginTop = 0
            marginBottom = Self.margin
            titleLabel.textColor = row.textColor ?? YT6SettingsStyle.buttonText
        case .account:
            marginTop = Self.margin
            marginBottom = 0
            titleLabel.textColor = YT6SettingsStyle.xDarkText
        }
        titleLabel.highlightedTextColor = titleLabel.textColor
        setNeedsLayout()
    }

    private func layoutContent(in box: CGRect) {
        let pad = Self.padding
        detailLabel.sizeToFit()
        checkmark.frame.origin = CGPoint(
            x: box.maxX - checkmark.frame.width,
            y: ((box.height - checkmark.frame.height) / 2).rounded()
        )
        detailLabel.frame.origin = CGPoint(
            x: box.maxX - pad - detailLabel.frame.width,
            y: ((box.height - detailLabel.frame.height) / 2).rounded()
        )
        let left = layoutLeading(in: box)
        let hasDetail = detailLabel.text?.isEmpty == false
        let right = hasDetail ? detailLabel.frame.minX - 8 : box.maxX - pad
        let height = titleLabel.font.lineHeight.rounded(.up)
        titleLabel.frame = CGRect(
            x: left,
            y: ((box.height - height) / 2).rounded(),
            width: max(right - left, 0),
            height: height
        )
    }

    /// The avatar or the color square, if any; returns where the title starts.
    private func layoutLeading(in box: CGRect) -> CGFloat {
        if kind == .account {
            let size = Self.avatarSize
            let top = ((box.height - size) / 2).rounded()
            avatar.frame = CGRect(x: Self.avatarLeft, y: top, width: size, height: size)
            return avatar.frame.maxX + Self.avatarLeft
        }
        guard !swatch.isHidden else {
            return Self.padding
        }
        let size = Self.swatchSize
        let top = ((box.height - size) / 2).rounded()
        swatch.frame = CGRect(x: Self.padding, y: top, width: size, height: size)
        return swatch.frame.maxX + 8
    }
}

/// A section title (`YTItemListHeader` @3f1120: `smallLightFont` (12) in
/// `XDarkTextColor`, 12 pt in, centered in its 36 pt row) or a note under a
/// section (APPROXIMATION: 2.0.0 settings have no footers; the note keeps
/// Opaline's attributions, in `smallLightFont` and `mediumTextColor`).
final class YT6SettingsTextCell: UITableViewCell {
    private static let padding: CGFloat = 12
    private let label = UILabel()
    private let isHeader: Bool

    init(text: String, isHeader: Bool) {
        self.isHeader = isHeader
        super.init(style: .default, reuseIdentifier: nil)
        backgroundColor = .clear
        selectionStyle = .none
        label.text = text
        label.font = YT6.smallLightFont
        label.textColor = isHeader ? YT6SettingsStyle.xDarkText : YT6SettingsStyle.mediumText
        label.numberOfLines = isHeader ? 1 : 0
        contentView.addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    static func noteHeight(_ text: String, width: CGFloat) -> CGFloat {
        let label = UILabel()
        label.font = YT6.smallLightFont
        label.numberOfLines = 0
        label.text = text
        let fit = CGSize(width: width - 2 * (padding + 8), height: .greatestFiniteMagnitude)
        return label.sizeThatFits(fit).height.rounded(.up) + 12
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let pad = Self.padding
        label.frame = isHeader
            ? bounds.insetBy(dx: pad, dy: 0)
            : bounds.insetBy(dx: pad + 8, dy: 6)
    }
}
