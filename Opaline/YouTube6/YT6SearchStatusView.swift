import UIKit

/// `YTFeedTableStatusView` as the search lists use it: a spinner while the
/// first page loads (`expandAndShowLoading` @3e96d8), the list's empty
/// message otherwise (`expandAndShowEmpty` @3e976c) — "No video results" and
/// the like (`status.empty.*`, @4b646/7145e/71508). The message is
/// `XLargeLightFont` (16), centered, up to six lines, 10 pt in from either
/// side (`initWithStyle:` @3e912e, `layoutSubviews` @3e9320).
///
/// APPROXIMATION: the light-background style (gray spinner, `darkTextColor`
/// #666) is assumed for the search lists; where the view sits in the empty
/// table (its minimum heights) is not read — content starts 10 pt below the
/// top, as the error image does (@3e9356).
final class YT6SearchStatusView: UIView {
    private static let inset: CGFloat = 10
    private static let maxLines = 6

    /// `topMargin` (@3e9356): room left at the top, for a header over it.
    var topMargin: CGFloat = 0 {
        didSet {
            setNeedsLayout()
        }
    }
    private let spinner = UIActivityIndicatorView(style: .gray)
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = YT6VideoRow.background
        spinner.hidesWhenStopped = true
        spinner.accessibilityLabel = YT6.string("feed.loading.access", fallback: "Loading…")
        label.font = YT6.xLargeLightFont
        label.textColor = YT6SearchSuggestionCell.textColor
        label.textAlignment = .center
        label.numberOfLines = Self.maxLines
        label.isHidden = true
        [spinner, label].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = Self.inset
        let top = topMargin + inset * 2
        spinner.center = CGPoint(x: bounds.midX, y: top + spinner.bounds.height / 2)
        let width = bounds.width - inset * 2
        let height = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            .height
        label.frame = CGRect(x: inset, y: top, width: width, height: height)
    }

    func showLoading() {
        isHidden = false
        label.isHidden = true
        spinner.startAnimating()
    }

    func showEmpty(_ message: String) {
        isHidden = false
        spinner.stopAnimating()
        label.text = message
        label.isHidden = false
        setNeedsLayout()
    }

    func hide() {
        spinner.stopAnimating()
        label.isHidden = true
    }
}

/// `YTItemListHeader` over the video results (`-[YTVideosFeedTableSectionController
/// headerView]` @3f4624): 36 pt (`+headerHeight` @3f165a), "VIDEOS"
/// (`item_list.videos`) in `smallLightFont` and `XDarkTextColor` (#333) 12 pt
/// in (`initWithTitle:` @3f11a0, `layoutSubviews` @3f1410); on the right,
/// flush, the "Refine" button on `settings_button`
/// (`-[YTSearchResultsViewController loadView]` @4b540, `+[UIButton
/// settingsButton]` @3f4d18).
///
/// The "· N" result count of 2.0.0 is left out: Opaline does not get the
/// total. APPROXIMATION: the header scrolls with the list (whether 2.0.0's
/// section header floats is not read) on the list background.
final class YT6SearchListHeader: UIView {
    static let height: CGFloat = 36
    private static let titleLeft: CGFloat = 12

    let refineButton = UIButton(type: .custom)
    private let title = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = YT6VideoRow.background
        title.font = YT6.smallLightFont
        title.textColor = UIColor(white: 51 / 255, alpha: 1)
        title.text = YT6.string("item_list.videos", fallback: "VIDEOS")
        refineButton.setImage(YT6.image("settings_button"), for: .normal)
        refineButton.showsTouchWhenHighlighted = true
        refineButton.sizeToFit()
        refineButton.accessibilityLabel = YT6.string("filters.refine.access", fallback: "Refine")
        [title, refineButton].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        title.sizeToFit()
        title.frame.origin = CGPoint(
            x: Self.titleLeft, y: ((bounds.height - title.frame.height) / 2).rounded()
        )
        refineButton.frame.origin = CGPoint(
            x: bounds.width - refineButton.frame.width,
            y: ((bounds.height - refineButton.frame.height) / 2).rounded()
        )
    }
}
