import UIKit

/// `YTSearchTextField` (`initWithFont:` @71688): the field of the 2.0.0
/// search bar. No border, `mediumLightFont` (13), "YouTube" as the hint
/// (`search.hint` @71700), no autocorrection, a Search return key and the
/// alert (dark) keyboard (@71734–717c2); the `search_hint` magnifier always on
/// the left and the `text_field_clear` cross on the right, shown only while
/// editing a non-empty query (`editingChanged:` @71c98).
final class YT6SearchField: UITextField {
    /// `-[YTSearchView_iPhone init]` @73532: horizontal and vertical padding.
    static let padding: CGFloat = 12
    /// `textRectForBounds:` @719ce: 7 pt off the width, then 7 pt inset.
    static let textInset: CGFloat = 7

    private let clearButton = UIButton(type: .custom)

    override var text: String? {
        didSet {
            // `-[YTSearchTextField setText:]` @71c20 re-checks the cross.
            updateClearButton()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        borderStyle = .none
        font = YT6.mediumLightFont
        placeholder = YT6.string("search.hint", fallback: "YouTube")
        autocorrectionType = .no
        returnKeyType = .search
        keyboardAppearance = .dark
        enablesReturnKeyAutomatically = true
        contentVerticalAlignment = .center
        leftView = UIImageView(image: YT6.image("search_hint"))
        leftViewMode = .always
        clearButton.setImage(YT6.image("text_field_clear"), for: .normal)
        clearButton.sizeToFit()
        clearButton.isHidden = true
        clearButton.accessibilityLabel = YT6.string("search.clear.access", fallback: "Clear search")
        clearButton.addTarget(self, action: #selector(clearPressed), for: .touchUpInside)
        rightView = clearButton
        rightViewMode = .always
        addTarget(self, action: #selector(updateClearButton), for: .editingChanged)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func textRect(forBounds bounds: CGRect) -> CGRect {
        var rect = super.textRect(forBounds: bounds)
        rect.size.width -= Self.textInset
        return rect.insetBy(dx: Self.textInset, dy: Self.padding)
    }

    /// `editingRectForBounds:` @71a14 returns the text rect.
    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        textRect(forBounds: bounds)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        textRect(forBounds: bounds)
    }

    /// `leftViewRectForBounds:` @71a58: `horizontalPadding` in, centered
    /// vertically (rounded up).
    override func leftViewRect(forBounds bounds: CGRect) -> CGRect {
        let size = (leftView as? UIImageView)?.image?.size ?? .zero
        let y = ((bounds.height - size.height) / 2).rounded(.up)
        return CGRect(origin: CGPoint(x: Self.padding, y: y), size: size)
    }

    /// `rightViewRectForBounds:` @71b30: `horizontalPadding` from the right
    /// edge, centered vertically (rounded down).
    override func rightViewRect(forBounds bounds: CGRect) -> CGRect {
        let size = clearButton.image(for: .normal)?.size ?? .zero
        let x = bounds.width - size.width - Self.padding
        let y = ((bounds.height - size.height) / 2).rounded(.down)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// `clearButtonPressed:` @71c64: empties the field and reports it as an
    /// edit, so the suggestions go back to the whole history.
    @objc
    private func clearPressed() {
        text = nil
        sendActions(for: .editingChanged)
    }

    @objc
    private func updateClearButton() {
        clearButton.isHidden = !isFirstResponder || (text ?? "").isEmpty
    }
}

/// `YTSearchSuggestionCell` (`initWithReuseIdentifier:` @3dc954): 36 pt rows
/// (`+cellHeight` @3dcd68), the text in `mediumLightFont` and
/// `darkTextColor` (#666) truncated in the middle, 10 pt in
/// (`layoutSubviews` @3dcb88); the `search_add` "append" arrow flush right.
/// Pressed, the row turns #666 with white text (`setHighlighted:` @3dcc1c).
final class YT6SearchSuggestionCell: UITableViewCell {
    static let reuseId = "kSuggestionCellId"
    static let height: CGFloat = 36
    /// `+[YTColor darkTextColor]` @3f5438.
    static let textColor = UIColor(white: 102 / 255, alpha: 1)
    private static let textLeft: CGFloat = 10
    /// `layoutSubviews` @3dcbd4: text width = cell width − 40 − 10.
    private static let textRightRoom: CGFloat = 40

    let appendButton = UIButton(type: .custom)
    private let label = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .default, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        appendButton.setImage(YT6.image("search_add"), for: .normal)
        appendButton.setImage(YT6.image("search_add_selected"), for: .highlighted)
        appendButton.sizeToFit()
        appendButton.accessibilityLabel = YT6.string(
            "search.append.access", fallback: "Append suggestion to search field"
        )
        contentView.addSubview(appendButton)
        label.font = YT6.mediumLightFont
        label.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(label)
        applyHighlight(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        appendButton.frame.origin = CGPoint(
            x: bounds.width - appendButton.frame.width,
            y: ((bounds.height - appendButton.frame.height) / 2).rounded()
        )
        let width = bounds.width - Self.textRightRoom - Self.textLeft
        let height = label.sizeThatFits(CGSize(width: width, height: bounds.height)).height
        label.frame = CGRect(
            x: Self.textLeft,
            y: ((bounds.height - height) / 2).rounded(),
            width: width,
            height: height
        )
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        applyHighlight(highlighted)
    }

    func configure(with suggestion: String) {
        label.text = suggestion
        setNeedsLayout()
    }

    private func applyHighlight(_ highlighted: Bool) {
        backgroundColor = highlighted ? Self.textColor : .white
        label.textColor = highlighted ? .white : Self.textColor
    }
}
