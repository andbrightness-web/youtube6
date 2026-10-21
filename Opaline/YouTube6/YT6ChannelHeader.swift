import UIKit

/// The channel page of 2.0.0 (`YTChannelViewController_iPhone`,
/// `YTChannelView_iPhone`, `YTChannelHeaderView_iPhone`).
/// Spec with addresses: ipodos27 research/YOUTUBE6-CHANNEL-2026-10-21.md.
extension YT6 {
    enum Channel {
        /// `-[YTChannelView_iPhone layoutSubviews]` @5ee9e: the banner strip.
        static let bannerHeight: CGFloat = 88
        /// @5eeec: the line under the banner, `channelBannerShadowColor`
        /// @3f587c (209, 209, 209).
        static let bannerShadowHeight: CGFloat = 1
        static let bannerShadow = UIColor(white: 209 / 255, alpha: 1)
        /// `+[YTChannelHeaderView_iPhone preferredHeight]` @3fd3ac.
        static let headerHeight: CGFloat = 66
        /// `-[YTChannelHeaderView_iPhone layoutSubviews]` @3fd1c8/3fd1e6:
        /// 44 pt thumbnail 8 pt in; names 8 pt right of it (@3fd2e6); the
        /// switch 8 pt from the right (@3fd2fc); label width is what is left
        /// less 40 (@3fd23c).
        static let thumbnailSize: CGFloat = 44
        static let padding: CGFloat = 8
        static let labelSlack: CGFloat = 40
        /// `initWithCreateSubscribeSwitch:` @3fcf42: `largeLightFont` (15).
        static let titleFont = UIFont(name: "HelveticaNeue-Light", size: 15)
            ?? .systemFont(ofSize: 15, weight: .light)
        /// `-[YTImageView setBorderStyle:]` @3fffe0: style 2 draws
        /// `thumbnail_border.png` at 0.16.
        static let borderAlpha: CGFloat = 0.16
        /// `YTFeedTableStatusView initWithStyle:` @3e9036/3e905e.
        static let statusFont = YT6.xLargeLightFont

        static var title: String {
            YT6.string("channel.title", fallback: "Channel")
        }
    }
}

/// `YTSubscribeSwitch` (style 0) drawn on upstream's subscribe button.
///
/// 110×30 (`sizeThatFits:` @400b18); a 17×17 icon (@4009b6) and the label
/// 5 pt right of it in `XSmallLightFont` (@400c2a, @40114c), the pair
/// centered and 1 pt low (@400cba). `setSubscribeState:` @400d9c: state 0 —
/// `subscribe` on `button_special`, white text; 1 (request running) — a
/// gray 0.75 spinner where the icon is, `button_light`; 4 — `subscribed`
/// on `button_light`; both in `darkTextColor`.
enum YT6SubscribeSwitch {
    enum State {
        case off, busy, on
    }

    static let size = CGSize(width: 110, height: 30)
    private static let iconSize = CGSize(width: 17, height: 17)
    private static let gap: CGFloat = 5

    static func prepare(_ button: UIButton) {
        button.layer.cornerRadius = 0
        button.backgroundColor = .clear
        button.contentEdgeInsets = .zero
        button.titleLabel?.font = YT6.xSmallLightFont
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        // The request-running state disables the button; it must not dim.
        button.adjustsImageWhenDisabled = false
        let half = gap / 2
        button.imageEdgeInsets = UIEdgeInsets(top: 1, left: -half, bottom: -1, right: half)
        button.titleEdgeInsets = UIEdgeInsets(top: 1, left: half, bottom: -1, right: -half)
    }

    static func apply(_ state: State, to button: UIButton, spinner: UIActivityIndicatorView) {
        let subscribed = state == .on
        let title = subscribed
            ? YT6.string("video_info.subscribed", fallback: "SUBSCRIBED")
            : YT6.string("video_info.subscribe", fallback: "SUBSCRIBE")
        button.setTitle(title, for: .normal)
        let color = state == .off ? UIColor.white : YT6.Watch.dark
        button.setTitleColor(color, for: .normal)
        button.setTitleColor(color, for: .disabled)
        let plate = state == .off ? "button_special" : "button_light"
        button.setBackgroundImage(YT6.stretchableImage(plate), for: .normal)
        switch state {
        case .off:
            button.setImage(icon("subscribe"), for: .normal)
        case .on:
            button.setImage(icon("subscribed"), for: .normal)
        case .busy:
            // An empty icon keeps the label where it was; the spinner sits
            // in its place.
            button.setImage(UIGraphicsImageRenderer(size: iconSize).image { _ in }, for: .normal)
        }
        if state == .busy {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
    }

    static func makeSpinner() -> UIActivityIndicatorView {
        let spinner = UIActivityIndicatorView(style: .gray)
        spinner.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        spinner.hidesWhenStopped = true
        spinner.isUserInteractionEnabled = false
        return spinner
    }

    /// The 16 pt icons drawn into the switch's 17 pt image view.
    private static func icon(_ name: String) -> UIImage? {
        guard let image = YT6.image(name) else {
            return nil
        }
        return UIGraphicsImageRenderer(size: iconSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: iconSize))
        }
        .withRenderingMode(.alwaysOriginal)
    }
}

/// Banner, its shadow line and the 66 pt header bar, laid out over
/// upstream's `ChannelHeaderView` subviews so its data binding keeps working
/// (`YTChannelView_iPhone layoutSubviews` @5ee34,
/// `YTChannelHeaderView_iPhone layoutSubviews` @3fd130).
final class YT6ChannelHeader: UIView {
    struct Parts {
        let banner: UIImageView
        let shadow: UIView
        let avatar: UIImageView
        let name: UILabel
        let subscribers: UILabel
        let button: UIButton
    }

    let parts: Parts
    let spinner = YT6SubscribeSwitch.makeSpinner()
    /// Height of the view holding this one; follows `hasBanner`.
    var heightConstraint: NSLayoutConstraint?
    /// `setHasBanner:` @5f104: no banner, the bar sits at the top.
    var hasBanner = false {
        didSet {
            guard hasBanner != oldValue else {
                return
            }
            heightConstraint?.constant = preferredHeight
            setNeedsLayout()
        }
    }

    var preferredHeight: CGFloat {
        let banner = YT6.Channel.bannerHeight + YT6.Channel.bannerShadowHeight
        return (hasBanner ? banner : 0) + YT6.Channel.headerHeight
    }

    private let bar = UIImageView(image: YT6.stretchableImage("channelbar"))
    private let border = UIImageView(image: YT6.stretchableImage("thumbnail_border"))

    init(parts: Parts) {
        self.parts = parts
        super.init(frame: .zero)
        backgroundColor = YT6VideoRow.background
        clipsToBounds = true
        border.alpha = YT6.Channel.borderAlpha
        [parts.banner, parts.shadow, bar, parts.avatar, border, parts.name, parts.subscribers]
            .forEach(addSubview)
        addSubview(parts.button)
        parts.button.addSubview(spinner)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        parts.banner.isHidden = !hasBanner
        parts.shadow.isHidden = !hasBanner
        var top: CGFloat = 0
        if hasBanner {
            parts.banner.frame = CGRect(x: 0, y: 0, width: width, height: YT6.Channel.bannerHeight)
            parts.shadow.frame = CGRect(
                x: 0,
                y: parts.banner.frame.maxY,
                width: width,
                height: YT6.Channel.bannerShadowHeight
            )
            top = parts.shadow.frame.maxY
        }
        bar.frame = CGRect(x: 0, y: top, width: width, height: YT6.Channel.headerHeight)
        layoutBar(bar.frame)
    }

    private func layoutBar(_ rect: CGRect) {
        let side = YT6.Channel.thumbnailSize
        let pad = YT6.Channel.padding
        let avatar = CGRect(x: rect.minX + pad, y: rect.midY - side / 2, width: side, height: side)
        parts.avatar.frame = avatar
        let hairline = 1 / UIScreen.main.scale
        border.frame = avatar.insetBy(dx: -hairline, dy: -hairline)
        let size = YT6SubscribeSwitch.size
        parts.button.frame = CGRect(
            x: rect.maxX - pad - size.width,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        parts.button.layoutIfNeeded()
        if let icon = parts.button.imageView {
            spinner.center = CGPoint(x: icon.frame.midX, y: icon.frame.midY)
        }
        let labelWidth = rect.width - side - size.width - YT6.Channel.labelSlack
        let nameHeight = parts.name.font.lineHeight.rounded(.up)
        let subsHeight = parts.subscribers.font.lineHeight.rounded(.up)
        let y = (rect.midY - (nameHeight + subsHeight) / 2).rounded()
        parts.name.frame = CGRect(x: avatar.maxX + pad, y: y, width: labelWidth, height: nameHeight)
        parts.subscribers.frame = CGRect(
            x: avatar.maxX + pad,
            y: parts.name.frame.maxY,
            width: labelWidth,
            height: subsHeight
        )
    }
}
