import UIKit

/// `YTGuideSectionHeader`: `section_background_guide.png` with the title in
/// `XXSmallLightFont`/`cellGuideSectionHeaderColor`, 10 pt from the left.
final class YT6GuideSectionHeader: UIView {
    private let background = UIImageView(image: YT6.stretchableImage("section_background_guide"))
    private let label = UILabel()

    init(text: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: YT6.guideWidth, height: YT6.guideHeaderHeight))
        addSubview(background)
        label.font = YT6.xxSmallLightFont
        label.textColor = YT6.guideSectionHeader
        label.backgroundColor = .clear
        label.text = text
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        label.sizeToFit()
        label.frame.origin = CGPoint(
            x: YT6.guideHeaderPadding,
            y: ((bounds.height - label.frame.height) / 2).rounded()
        )
    }
}

/// `YTBaseGuideCell`: background plate (`cell_background_guide[_selected]`,
/// `_tap` while pressed), 35 pt icon at (7, 10), title 10 pt right of it,
/// 168 wide, `XLargeLightFont`, gray / white when selected.
final class YT6GuideCell: UITableViewCell {
    struct Content {
        var title: String
        var icon: String?
        var selected = false
        var disclosure: String?
        /// A channel's avatar instead of a 2.0.0 icon, under
        /// `thumbnail_mask_guide` (`guideUserThumbnailMaskWithSelected:`).
        var avatarURL: String?
    }

    static let reuseID = "YT6GuideCell"

    var onDisclosure: (() -> Void)?
    private let plate = UIImageView()
    private let icon = ThumbnailImageView(frame: .zero)
    private let avatarMask = UIImageView()
    private let title = UILabel()
    private let disclosureButton = UIButton(type: .custom)
    private var isEntrySelected = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = YT6.guideBackground
        backgroundView = plate
        icon.contentMode = .center
        icon.clipsToBounds = true
        contentView.addSubview(icon)
        contentView.addSubview(avatarMask)
        title.font = YT6.xLargeLightFont
        title.backgroundColor = .clear
        contentView.addSubview(title)
        disclosureButton.addTarget(self, action: #selector(tapDisclosure), for: .touchUpInside)
        contentView.addSubview(disclosureButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(_ content: Content) {
        isEntrySelected = content.selected
        title.text = content.title
        icon.cancel()
        if let avatar = content.avatarURL.flatMap({ URL(string: $0) }) {
            icon.image = nil
            icon.contentMode = .scaleAspectFill
            icon.setImage(url: avatar)
            let mask = content.selected ? "thumbnail_mask_guide_selected" : "thumbnail_mask_guide"
            avatarMask.image = YT6.stretchableImage(mask)
            avatarMask.isHidden = false
        } else {
            icon.contentMode = .center
            let suffix = content.selected ? "_selected" : ""
            icon.image = content.icon.flatMap { YT6.image($0 + suffix) }
            avatarMask.isHidden = true
        }
        disclosureButton.setImage(content.disclosure.flatMap(YT6.image), for: .normal)
        disclosureButton.isHidden = content.disclosure == nil
        onDisclosure = nil
        updatePressedAppearance()
        setNeedsLayout()
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        updatePressedAppearance()
    }

    /// `-[YTBaseGuideCell updatePressedAppearance]` @5c8cc.
    private func updatePressedAppearance() {
        plate.image = YT6.stretchableImage(
            isHighlighted ? "cell_background_guide_tap"
                : isEntrySelected ? "cell_background_guide_selected" : "cell_background_guide"
        )
        title.textColor = isEntrySelected ? YT6.guideTitleSelected : YT6.guideTitle
    }

    @objc
    private func tapDisclosure() {
        onDisclosure?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = YT6.guideIconSize
        icon.frame = CGRect(origin: YT6.guideIconOrigin, size: CGSize(width: size, height: size))
        avatarMask.frame = icon.frame
        let lineHeight = title.font.lineHeight.rounded(.up)
        title.frame = CGRect(
            x: icon.frame.maxX + YT6.guideTitleGap,
            y: (icon.frame.midY - lineHeight / 2).rounded(),
            width: YT6.guideTitleWidth,
            height: lineHeight
        )
        // APPROXIMATION: disclosure button right-aligned in a 44 pt square.
        disclosureButton.frame = CGRect(
            x: YT6.guideWidth - 44, y: (bounds.height - 44) / 2, width: 44, height: 44
        )
    }
}
