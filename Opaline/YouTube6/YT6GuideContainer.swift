import UIKit

/// `YTGuideContainerView` on iPhone: the guide lies under the content on the
/// left; the content (the hidden-tab-bar `MainTabBarController`) slides right
/// by the guide width to reveal it. Pan on a root screen drags it, a tap on
/// the uncovered content closes it. APPROXIMATION: no `bounceWithOffset:` yet.
///
/// The player panel stays above both — it is a child of the root container
/// added after this, so nothing here moves it.
final class YT6GuideContainer: NSObject, UIGestureRecognizerDelegate {
    private weak var root: RootContainerViewController?
    private let tabs: MainTabBarController
    let guide = YT6GuideViewController()
    private let shield = UIButton(type: .custom)
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
    private var panStartOffset: CGFloat = 0

    private(set) var isOpen = false

    private var content: UIView { tabs.view }

    init(root: RootContainerViewController, tabs: MainTabBarController) {
        self.root = root
        self.tabs = tabs
        super.init()
    }

    /// Called from the root container's `viewDidLoad`, after the tab bar
    /// controller's view is in place.
    func install() {
        guard let root else {
            return
        }
        root.addChild(guide)
        let height = root.view.bounds.height
        guide.view.frame = CGRect(x: 0, y: 0, width: YT6.guideWidth, height: height)
        guide.view.autoresizingMask = [.flexibleHeight, .flexibleRightMargin]
        root.view.insertSubview(guide.view, belowSubview: content)
        guide.didMove(toParent: root)
        guide.view.isHidden = true
        guide.select(tabs.yt6SelectedSection ?? .whatToWatch)
        guide.onSelect = { [weak self] row in self?.handle(row) }

        // APPROXIMATION: the content edge shadow is not yet measured.
        content.layer.shadowColor = UIColor.black.cgColor
        content.layer.shadowOpacity = 0.6
        content.layer.shadowRadius = 4
        content.layer.shadowOffset = CGSize(width: -2, height: 0)

        shield.addTarget(self, action: #selector(close), for: .touchUpInside)
        shield.isHidden = true
        content.addSubview(shield)

        pan.delegate = self
        content.addGestureRecognizer(pan)
        decorateSelectedSection()
    }

    /// Same list chrome on every guide row (REQUEST691): runs once the
    /// selected row's screen has loaded its list.
    private func decorateSelectedSection() {
        DispatchQueue.main.async { [weak self] in
            guard let root = (self?.tabs.selectedViewController as? UINavigationController)?
                .viewControllers.first
            else {
                return
            }
            // A row opened for the first time has not loaded its screen yet;
            // skipping it left «My Subscriptions» with upstream's dark
            // refresh area and spinner (REQUEST700).
            root.loadViewIfNeeded()
            YT6PullRefresh.attach(under: root.view)
            YT6TapThrough.attach(under: root.view)
        }
    }

    // MARK: Open / close (`maximize` / `minimize`)

    @objc
    func toggle() {
        if isOpen {
            close()
        } else {
            open()
        }
    }

    func open() {
        guide.reloadChannels()
        setOffset(YT6.guideWidth, animated: true)
    }

    @objc
    func close() {
        setOffset(0, animated: true)
    }

    private func setOffset(_ offset: CGFloat, animated: Bool) {
        let opening = offset > 0
        guide.view.isHidden = false
        if opening {
            guide.tableView.scrollsToTop = true
            content.layer.shadowPath = UIBezierPath(rect: content.bounds).cgPath
        }
        let changes = {
            self.moveContent(to: offset)
        }
        let done: (Bool) -> Void = { _ in
            self.isOpen = opening
            self.guide.view.isHidden = !opening
            self.shield.isHidden = !opening
            self.shield.frame = self.content.bounds
            self.content.bringSubviewToFront(self.shield)
            self.root?.setNeedsStatusBarAppearanceUpdate()
        }
        guard animated else {
            changes()
            done(true)
            return
        }
        UIView.animate(
            withDuration: YT6.guideSlideDuration,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
            animations: changes,
            completion: done
        )
    }

    // MARK: Rows

    private func handle(_ row: YT6GuideViewController.Row) {
        switch row {
        case .section(let section):
            tabs.yt6Select(section)
            close()
            decorateSelectedSection()
        case .account:
            close()
            topScreen()?.toolbarOpenProfile()
        case .channel(let index):
            showChannel(guide.channels[index])
        case .settings:
            close()
            topScreen()?.toolbarOpenSettings()
        }
    }

    /// A channel picked in the guide opens on top of My Subscriptions.
    private func showChannel(_ channel: SubscribedChannel) {
        tabs.yt6Select(.subscriptions)
        close()
        guard let nav = tabs.selectedViewController as? UINavigationController,
              let root = nav.viewControllers.first
        else {
            return
        }
        let page = tabs.dependencies.makeChannelViewController(
            channelId: channel.id,
            channelName: channel.title
        )
        nav.setViewControllers([root, page], animated: false)
        decorateSelectedSection()
    }

    private func topScreen() -> UIViewController? {
        (tabs.selectedViewController as? UINavigationController)?.topViewController
    }

    // MARK: Pan (`pan:`, `bounceWithOffset:`)

    /// The watch page belongs to the content area in 2.0.0 (`YTContentView`)
    /// and slides aside with it (REQUEST704). Its controller has to stay a
    /// child of the root container — a view of it inside the tab bar
    /// controller's view crashed UIKit on opening a video (REQUEST707) — so
    /// it is moved by the same offset, and lets touches through to the
    /// content's close shield while the guide is open.
    private func moveContent(to x: CGFloat) {
        content.frame.origin.x = x
        let page = root?.children.compactMap { $0 as? PlayerPanelViewController }.first?.view
        page?.frame.origin.x = x
        page?.isUserInteractionEnabled = x == 0
    }

    @objc
    private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let width = YT6.guideWidth
        switch gesture.state {
        case .began:
            panStartOffset = content.frame.origin.x
            guide.view.isHidden = false
            content.layer.shadowPath = UIBezierPath(rect: content.bounds).cgPath
        case .changed:
            let x = panStartOffset + gesture.translation(in: root?.view).x
            moveContent(to: min(max(x, 0), width))
        case .ended, .cancelled:
            let velocity = gesture.velocity(in: root?.view).x
            let x = content.frame.origin.x
            let shouldOpen = abs(velocity) > 300 ? velocity > 0 : x > width / 2
            setOffset(shouldOpen ? width : 0, animated: true)
        default:
            break
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan else {
            return true
        }
        let velocity = pan.velocity(in: root?.view)
        guard abs(velocity.x) > abs(velocity.y) else {
            return false
        }
        if isOpen {
            return true
        }
        // Only a rightward drag on a root screen opens the guide; deeper
        // screens keep the system edge swipe for "back".
        let nav = tabs.selectedViewController as? UINavigationController
        return velocity.x > 0 && (nav?.viewControllers.count ?? 1) == 1
    }
}
