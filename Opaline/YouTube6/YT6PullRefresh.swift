import UIKit

/// 2.0.0 pull-to-refresh (`YTPullRefreshHeader` → `GIPPullRefreshView`,
/// `initWithStyle:` @3eba8c): the `refresh_light` arrow turning as the list
/// is pulled, "Pull down to refresh" / "Release to refresh" in
/// `XLargeLightFont` (16) and `mediumTextColor` (153), a spinner while
/// loading.
///
/// Upstream's `UIRefreshControl` stays the mechanism — it triggers the
/// reload and holds the inset while loading — but is made invisible; this
/// header only draws, following the offset and `isRefreshing`. Attached the
/// same way to every guide row, so all lists pull alike (REQUEST691).
final class YT6PullRefresh: UIView {
    private static var key: UInt8 = 0
    /// APPROXIMATION: `GIPPullRefreshView pullHeight` not yet read.
    private static let height: CGFloat = 60

    private weak var scrollView: UIScrollView?
    private let arrow = UIImageView(image: YT6.image("refresh_light"))
    private let spinner = UIActivityIndicatorView(style: .gray)
    private let status = UILabel()
    private var observation: NSKeyValueObservation?
    /// Top inset with the list at rest — the refresh control adds its own
    /// height while loading, which must not read as "no pull".
    private var restingTop: CGFloat = 0
    private var showsRelease = false

    private init(scrollView: UIScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        status.font = YT6.xLargeLightFont
        status.textColor = YT6.guideTitle
        status.backgroundColor = .clear
        [arrow, spinner, status].forEach(addSubview)
        observation = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in
            self?.update()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Every scroll view under `root` that has a refresh control gets the
    /// 2.0.0 header (once) and the light list background.
    static func attach(under root: UIView) {
        var stack = [root]
        while let view = stack.popLast() {
            stack += view.subviews
            guard let scroll = view as? UIScrollView,
                  let control = scroll.refreshControl,
                  objc_getAssociatedObject(scroll, &key) == nil
            else {
                continue
            }
            control.tintColor = .clear
            control.attributedTitle = nil
            scroll.backgroundColor = YT6VideoRow.background
            let header = YT6PullRefresh(scrollView: scroll)
            scroll.addSubview(header)
            objc_setAssociatedObject(scroll, &key, header, .OBJC_ASSOCIATION_RETAIN)
            header.update()
        }
    }

    private func update() {
        guard let scrollView, let control = scrollView.refreshControl else {
            return
        }
        let loading = control.isRefreshing
        if !loading, !scrollView.isDragging, !scrollView.isDecelerating {
            restingTop = scrollView.adjustedContentInset.top
        }
        let pull = max(-(scrollView.contentOffset.y + restingTop), 0)
        frame = CGRect(x: 0, y: -pull, width: scrollView.bounds.width, height: pull)
        isHidden = pull == 0
        if loading {
            spinner.startAnimating()
        } else {
            spinner.stopAnimating()
        }
        arrow.isHidden = loading
        let release = pull > Self.height
        status.text = statusText(loading: loading, release: release)
        if release != showsRelease {
            showsRelease = release
            UIView.animate(withDuration: 0.2) {
                self.arrow.transform = release ? CGAffineTransform(rotationAngle: .pi) : .identity
            }
        }
        setNeedsLayout()
    }

    private func statusText(loading: Bool, release: Bool) -> String {
        if loading {
            return YT6.string("feed.loading.access", fallback: "Loading…")
        }
        return release
            ? YT6.string("pull_refresh.release", fallback: "Release to refresh")
            : YT6.string("pull_refresh.drag", fallback: "Pull down to refresh")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        status.sizeToFit()
        let band = CGRect(
            x: 0,
            y: bounds.height - Self.height,
            width: bounds.width,
            height: Self.height
        )
        status.center = CGPoint(x: band.midX + 12, y: band.midY)
        arrow.center = CGPoint(x: status.frame.minX - 24, y: band.midY)
        spinner.center = arrow.center
    }
}
