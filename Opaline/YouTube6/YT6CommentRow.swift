import UIKit

/// `YTCommentCell` (`initWithReuseIdentifier:` @3ce97c, `layoutSubviews`
/// @3cee20, `+cellHeightForEntry:width:` @3cf3b0): a `comment_bubble`
/// (`commentBubbleImageView` @405174, stretchable) `cw − 24` wide, 12 pt in
/// at the top of the row; inside it, 16 pt in and 8 pt down, the title line
/// — author bottom-left in `mediumLightFont` `linkColor`, age bottom-right in
/// `smallLightFont` `mediumTextColor` — and 8 pt under that the text,
/// `mediumLightFont` `darkTextColor`, any number of lines, word wrap,
/// `cw − 48` wide. Bubble height: title + text + 24; row: title + text + 36.
/// No avatar and no replies: 2.0.0 comments are one flat level.
final class YT6CommentRow: YT6CommentsCardRow {
    private static let bubbleInset: CGFloat = 12
    private static let textInset: CGFloat = 16
    private static let gap: CGFloat = 8

    /// max(13 pt, 12 pt line) — the title view's height (@3cef66…3cefc8).
    private static var titleHeight: CGFloat {
        max(YT6.mediumLightFont.lineHeight, YT6.smallLightFont.lineHeight).rounded(.up)
    }

    private let bubble = UIImageView(image: YT6.stretchableImage("comment_bubble"))
    private let author = UILabel()
    private let age = UILabel()
    private let content = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        author.font = YT6.mediumLightFont
        author.textColor = YT6.Watch.link
        age.font = YT6.smallLightFont
        age.textColor = YT6.Watch.medium
        age.textAlignment = .right
        content.font = YT6.mediumLightFont
        content.textColor = YT6.Watch.dark
        content.numberOfLines = 0
        content.lineBreakMode = .byWordWrapping
        [bubble, author, age, content].forEach(addSubview)
        isAccessibilityElement = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// `+contentSize:width:font:` @3cf52c: `sizeWithFont:constrainedToSize:
    /// lineBreakMode:` at `cw − 48`.
    private static func contentHeight(_ text: String, contentWidth: CGFloat) -> CGFloat {
        guard !text.isEmpty else {
            return 0
        }
        let string = NSAttributedString(string: text, attributes: [.font: YT6.mediumLightFont])
        let box = string.boundingRect(
            with: CGSize(width: contentWidth - 48, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            context: nil
        )
        return box.height.rounded(.up)
    }

    /// Row height for a card `width` wide (the plate's 3 pt sides included).
    static func height(for comment: Comment, width: CGFloat) -> CGFloat {
        let contentWidth = width - outset * 2
        return titleHeight + 36 + contentHeight(comment.content, contentWidth: contentWidth)
    }

    func configure(_ comment: Comment) {
        author.text = comment.authorName
        age.text = comment.publishedTime
        content.text = comment.content
        accessibilityLabel = [comment.authorName, comment.publishedTime, comment.content]
            .compactMap { $0 }
            .joined(separator: ", ")
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let cw = contentWidth
        let left = Self.outset + Self.bubbleInset
        let textWidth = cw - 48
        let title = Self.titleHeight
        let textHeight = Self.contentHeight(content.text ?? "", contentWidth: cw)
        bubble.frame = CGRect(x: left, y: 0, width: cw - 24, height: title + textHeight + 24)
        let titleY = Self.gap
        let textX = left + Self.textInset
        age.sizeToFit()
        let ageWidth = min(age.frame.width, textWidth)
        age.frame = CGRect(
            x: textX + textWidth - ageWidth,
            y: titleY,
            width: ageWidth,
            height: title
        )
        author.frame = CGRect(x: textX, y: titleY, width: textWidth - ageWidth - 4, height: title)
        content.frame = CGRect(
            x: textX,
            y: titleY + title + Self.gap,
            width: textWidth,
            height: textHeight
        )
    }
}

/// `YTAddCommentCell` (`init` @3fac3c, `layoutSubviews` @3fb198,
/// `sizeThatFits:` @3fb3e8): the user's 34×34 thumbnail 12 pt in at the top
/// left (`borderStyle 2`), the `comment_box` (`commentInputImageView`
/// @40511c) `cw − 36 − 34` = 234 wide at the top right 12 pt in, and the
/// text field inside it 12 pt in, `mediumLightFont` `darkTextColor`,
/// placeholder «Добавить комментарий…». Height 34 + 24.
final class YT6AddCommentRow: YT6CommentsCardRow, UITextFieldDelegate {
    static let height: CGFloat = 58
    private static let boxHeight: CGFloat = 34

    /// A tap on the field: upstream has no API to post a comment.
    var onTap: (() -> Void)?

    let thumbnail = UIImageView()
    private let box = UIImageView(image: YT6.stretchableImage("comment_box"))
    private let field = UITextField()

    override init(frame: CGRect) {
        super.init(frame: frame)
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        // `-[YTImageView setBorderStyle:]` @3fffb0: style 2 is the border
        // view at alpha 0.16. APPROXIMATION: drawn as a 1 px black line.
        thumbnail.layer.borderWidth = 1 / UIScreen.main.scale
        thumbnail.layer.borderColor = UIColor(white: 0, alpha: 0.16).cgColor
        field.font = YT6.mediumLightFont
        field.textColor = YT6.Watch.dark
        field.contentVerticalAlignment = .center
        field.returnKeyType = .done
        field.keyboardAppearance = .dark
        field.delegate = self
        // APPROXIMATION: the placeholder keeps iOS 6's own gray (0.7).
        field.attributedPlaceholder = NSAttributedString(
            string: YT6.string("watch.comments.input_hint", fallback: "Add a comment…"),
            attributes: [.foregroundColor: UIColor(white: 0.7, alpha: 1)]
        )
        [thumbnail, box, field].forEach(addSubview)
        setUserThumbnail(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// `updateUserThumbnail:` @3efec8: `default_user_thumbnail` until the
    /// signed-in user's own picture is known.
    func setUserThumbnail(_ image: UIImage?) {
        thumbnail.image = image ?? YT6.image("default_user_thumbnail")
    }

    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        onTap?()
        return false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let out = Self.outset
        let side = YT6.Watch.padding
        let size = Self.boxHeight
        let boxWidth = contentWidth - side * 2 - size - side
        thumbnail.frame = CGRect(x: out + side, y: side, width: size, height: size)
        box.frame = CGRect(
            x: out + contentWidth - side - boxWidth,
            y: side,
            width: boxWidth,
            height: size
        )
        field.frame = box.frame.insetBy(dx: side, dy: 0)
    }
}
