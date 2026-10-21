import UIKit

/// The title strip of `YTTabsView` (`YTTabTitlesView`) on the search results
/// screen: VIDEOS, PLAYLISTS, CHANNELS (`-[YTSearchResultsView_iPhone
/// initWithVideosView:]` @713f2/714b4/71552). The strip is as tall as
/// `tab_titles_background` (`preferredHeight` @40422c) and tiles it
/// (`init` @40392c); each title is a button on `tab_titles_button` /
/// `_selected` (the red underline) in `smallLightFont` and `darkTextColor`,
/// shrinking to fit (`buttonWithTitle:` @404294), with `tab_separator`
/// between them. Switching is by tap only — `YTTabsView init` turns the
/// swipe off (@4028c0). Under the strip lies `bar_shadow` (@402886).
final class YT6SearchTabsView: UIView {
    /// `buttonWithTitle:` @4043ce: 2 pt either side of the title.
    private static let titleInsets = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)

    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex = 0
    private var buttons: [UIButton] = []
    private var separators: [UIImageView] = []
    let shadow = UIImageView(image: YT6.stretchableImage("bar_shadow"))

    var preferredHeight: CGFloat {
        YT6.image("tab_titles_background")?.size.height ?? 44
    }

    init(titles: [String]) {
        super.init(frame: .zero)
        if let tile = YT6.image("tab_titles_background") {
            backgroundColor = UIColor(patternImage: tile)
        }
        for (index, title) in titles.enumerated() {
            let button = makeButton(title: title)
            button.tag = index
            buttons.append(button)
            addSubview(button)
            if index > 0 {
                let separator = UIImageView(image: YT6.image("tab_separator"))
                separators.append(separator)
                addSubview(separator)
            }
        }
        select(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// APPROXIMATION: equal widths; `YTTabTitlesView layoutSubviews`
    /// @403a8c (minimum title width, font fitting) is not read through.
    override func layoutSubviews() {
        super.layoutSubviews()
        guard !buttons.isEmpty else {
            return
        }
        let width = bounds.width / CGFloat(buttons.count)
        for (index, button) in buttons.enumerated() {
            let x = (width * CGFloat(index)).rounded()
            let next = (width * CGFloat(index + 1)).rounded()
            button.frame = CGRect(x: x, y: 0, width: next - x, height: bounds.height)
        }
        for (index, separator) in separators.enumerated() {
            let size = separator.image?.size ?? CGSize(width: 1, height: bounds.height)
            separator.frame = CGRect(
                x: buttons[index + 1].frame.minX - size.width / 2,
                y: 0,
                width: size.width,
                height: bounds.height
            )
        }
    }

    /// `setCurrentTitleIndex:` @4040e0: only the current title is selected.
    func select(_ index: Int) {
        selectedIndex = index
        for button in buttons {
            button.isSelected = button.tag == index
        }
    }

    private func makeButton(title: String) -> UIButton {
        let button = UIButton(type: .custom)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = YT6.smallLightFont
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.setTitleColor(YT6SearchSuggestionCell.textColor, for: .normal)
        button.adjustsImageWhenHighlighted = false
        button.titleEdgeInsets = Self.titleInsets
        button.setBackgroundImage(YT6.image("tab_titles_button"), for: .normal)
        button.setBackgroundImage(YT6.image("tab_titles_button_selected"), for: .selected)
        button.setBackgroundImage(
            YT6.image("tab_titles_button_selected"), for: [.selected, .highlighted]
        )
        button.addTarget(self, action: #selector(pressed(_:)), for: .touchUpInside)
        return button
    }

    /// `didPressButton:` @404500 → `didTouchTitleAtIndex:`.
    @objc
    private func pressed(_ sender: UIButton) {
        guard sender.tag != selectedIndex else {
            return
        }
        select(sender.tag)
        onSelect?(sender.tag)
    }
}
