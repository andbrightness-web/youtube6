import UIKit

/// `YTTabTitlesView` over the channel's lists (`YTTabsView`, swipe off —
/// `setSwipeEnabled:NO` @4028b8, tabs change by tap only).
///
/// Height of `tab_titles_background.png` (`preferredHeight` @40422c), which
/// is also its pattern background (`init` @40394a). Buttons share the width
/// equally with a `tab_separator.png` between them, the last taking what is
/// left (`layoutSubviews` @403b8e–403dd2); each on `tab_titles_button.png`,
/// `_selected` when current, title in `smallLightFont` `darkTextColor`,
/// 2 pt side insets, shrinking to fit (`buttonWithTitle:` @404294).
/// `bar_shadow.png` lies over the list under the titles
/// (`YTTabsView layoutSubviews` @402dbc–402dd0).
final class YT6ChannelTabs: UIView {
    static let height: CGFloat = 44

    var onSelect: ((Int) -> Void)?
    private(set) var selectedIndex = 0

    private var buttons: [UIButton] = []
    private var separators: [UIImageView] = []
    private let shadow = UIImageView(image: YT6.stretchableImage("bar_shadow"))

    init(titles: [String]) {
        super.init(frame: .zero)
        if let pattern = YT6.image("tab_titles_background") {
            backgroundColor = UIColor(patternImage: pattern)
        }
        buttons = titles.enumerated().map { Self.makeButton($1, tag: $0) }
        separators = buttons.dropFirst().map { _ in UIImageView(image: YT6.image("tab_separator")) }
        for button in buttons {
            button.addTarget(self, action: #selector(tap(_:)), for: .touchUpInside)
            addSubview(button)
        }
        separators.forEach(addSubview)
        addSubview(shadow)
        select(0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func makeButton(_ title: String, tag: Int) -> UIButton {
        let button = UIButton(type: .custom)
        button.tag = tag
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = YT6.smallLightFont
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.setTitleColor(YT6.Watch.dark, for: .normal)
        button.adjustsImageWhenHighlighted = false
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 2, bottom: 0, right: 2)
        let normal = YT6.image("tab_titles_button")
        let selected = YT6.image("tab_titles_button_selected")
        button.setBackgroundImage(normal, for: .normal)
        button.setBackgroundImage(selected, for: .selected)
        button.setBackgroundImage(selected, for: [.selected, .highlighted])
        return button
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !buttons.isEmpty else {
            return
        }
        let separatorWidth = separators.first?.image?.size.width ?? 1
        let free = bounds.width - CGFloat(separators.count) * separatorWidth
        let width = (free / CGFloat(buttons.count)).rounded(.down)
        var x: CGFloat = 0
        for (index, button) in buttons.enumerated() {
            let isLast = index == buttons.count - 1
            let buttonWidth = isLast ? bounds.width - x : width
            button.frame = CGRect(x: x, y: 0, width: buttonWidth, height: bounds.height)
            x += buttonWidth
            if index < separators.count {
                separators[index].frame = CGRect(
                    x: x, y: 0, width: separatorWidth, height: bounds.height
                )
                x += separatorWidth
            }
        }
        let shadowHeight = shadow.image?.size.height ?? 2
        shadow.frame = CGRect(x: 0, y: bounds.height, width: bounds.width, height: shadowHeight)
    }

    func select(_ index: Int) {
        selectedIndex = index
        for button in buttons {
            button.isSelected = button.tag == index
        }
    }

    @objc
    private func tap(_ sender: UIButton) {
        guard sender.tag != selectedIndex else {
            return
        }
        select(sender.tag)
        onSelect?(sender.tag)
    }
}
