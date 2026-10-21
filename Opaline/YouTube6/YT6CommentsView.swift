import UIKit

/// The rows of `YTCommentsFeedTableSectionController` (@3ee7c0) under the
/// «КОММЕНТАРИИ · N» header card: row 1 `YTAddCommentCell`, rows 2+
/// `YTCommentCell`s (`cellForRow:` @3eebdc, `numberOfRows` @3eeb54 — the
/// input row is there collapsed too, only the comments come and go with
/// `setExpanded:` @3ef578). One card with the header: every row is a
/// `YTTableViewCell` whose plate is its content ±3 pt
/// (`layoutSubviews` @3dd57c), so the plates join into one column.
/// Frame based: a long thread adds a few hundred views, and nothing here
/// needs Auto Layout's solving.
final class YT6CommentsView: UIView {
    enum Row {
        case comment(Comment)
        /// `YTFeedTableStatusView`: a spinner when `nil`, else a message.
        case status(String?)
    }

    /// Below the last row of the section (`setPosition:` @3cf34c/3fb5a4:
    /// marginBottom 4 at position 2, the bottom).
    static let bottomMargin: CGFloat = 4

    let addRow = YT6AddCommentRow()
    var heightConstraint: NSLayoutConstraint?

    private var rows: [Row] = []
    private var commentViews: [YT6CommentRow] = []
    private let statusView = YT6CommentStatusRow()
    private var laidOutWidth: CGFloat = 0
    private var dirty = true

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        addSubview(addRow)
        addSubview(statusView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func setRows(_ newRows: [Row]) {
        rows = newRows
        dirty = true
        setNeedsLayout()
        layoutRows()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if dirty || laidOutWidth != bounds.width {
            layoutRows()
        }
    }

    /// Stacks the rows, picks each plate by its place (`setPositionForRow:
    /// rowsInSection:` @3dd9c4: top 0, middle 1, bottom 2) and sets the height.
    private func layoutRows() {
        let width = bounds.width
        guard width > 0 else {
            return
        }
        dirty = false
        laidOutWidth = width
        let items = [(addRow as YT6CommentsCardRow, YT6AddCommentRow.height)] + rowItems(width)
        var y: CGFloat = 0
        for (index, item) in items.enumerated() {
            let margin = index == items.count - 1 ? Self.bottomMargin : 0
            let name = margin > 0 ? "grouped_table_card_bottom" : "grouped_table_card_last"
            item.0.isHidden = false
            item.0.frame = CGRect(x: 0, y: y, width: width, height: item.1 + margin)
            item.0.setPlate(name, margin: margin)
            y += item.1 + margin
        }
        if heightConstraint?.constant != y {
            heightConstraint?.constant = y
        }
    }

    /// The comment and status rows with their heights; views past the
    /// current rows are hidden for reuse.
    private func rowItems(_ width: CGFloat) -> [(YT6CommentsCardRow, CGFloat)] {
        var used = 0
        statusView.isHidden = true
        let items: [(YT6CommentsCardRow, CGFloat)] = rows.map { row in
            switch row {
            case .comment(let comment):
                let view = commentView(at: used)
                used += 1
                view.configure(comment)
                return (view, YT6CommentRow.height(for: comment, width: width))
            case .status(let text):
                statusView.configure(text: text)
                return (statusView, YT6CommentStatusRow.height)
            }
        }
        commentViews.dropFirst(used).forEach { $0.isHidden = true }
        return items
    }

    private func commentView(at index: Int) -> YT6CommentRow {
        if index < commentViews.count {
            return commentViews[index]
        }
        let view = YT6CommentRow()
        addSubview(view)
        commentViews.append(view)
        return view
    }
}

/// A row of the comments card: the plate (content ±3 pt) behind whatever
/// the row draws. Rows are laid out in the card's frame, which already
/// carries the plate's 3 pt sides, so content starts 3 pt in.
class YT6CommentsCardRow: UIView {
    static let outset = YT6.Watch.plateOutset

    let plate = UIImageView()
    private var plateName = ""
    private var margin: CGFloat = 0

    /// The width the row's content gets (`contentView.width`).
    var contentWidth: CGFloat {
        bounds.width - Self.outset * 2
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        addSubview(plate)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// `+[YTUIResources groupedTableBackgroundImageWithPosition:…]` @404bf4:
    /// a middle row of a separator-style-1 cell takes `_last` (no line), the
    /// bottom row `_bottom`. Both comment cells set style 1 (@3ce9d0, @3fac8a).
    func setPlate(_ name: String, margin: CGFloat) {
        self.margin = margin
        if plateName != name {
            plateName = name
            plate.image = YT6.stretchableImage(name)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let out = Self.outset
        plate.frame = CGRect(
            x: 0,
            y: -out,
            width: bounds.width,
            height: bounds.height - margin + out * 2
        )
    }
}

/// `YTFeedTableStatusView` at the tail of the feed: the gray spinner while
/// a page loads, the empty message (`XLargeLightFont`, `mediumTextColor`,
/// centered — `initWithStyle:` @3e8f70) when there is nothing.
final class YT6CommentStatusRow: YT6CommentsCardRow {
    /// APPROXIMATION: the status view's own height (`sizeThatFits:` @3e9530)
    /// is not read; one 44 pt line.
    static let height: CGFloat = 44

    private let spinner = UIActivityIndicatorView(style: .gray)
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = YT6.xLargeLightFont
        label.textColor = YT6.Watch.medium
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        addSubview(spinner)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(text: String?) {
        label.text = text
        label.isHidden = text == nil
        if text == nil {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let out = Self.outset
        let line = CGRect(x: out, y: 0, width: contentWidth, height: Self.height)
        spinner.center = CGPoint(x: line.midX, y: line.midY)
        label.frame = line.insetBy(dx: YT6.Watch.padding, dy: 0)
    }
}
