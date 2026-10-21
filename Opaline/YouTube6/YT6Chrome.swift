import UIKit

/// The 2.0.0 title bar and its buttons.
///
/// `-[YTNavigation_iPhone setupUIAppearanceOverrides]` @238dc: title in
/// `XLargeLightFont` and `titleBarTextColor` with a clear shadow,
/// `titleBarBackgroundImage` (`titlebar.png`, stretchable) as the bar
/// background, `backButton` (`back_button.png`, stretchable) behind "Back".
/// Bar buttons are `navGuideImage` (`guide.png`) on the left of a root screen
/// and `navSearchImage` (`search.png`) on the right.
enum YT6Chrome {
    static func styleNavigationBar(_ bar: UINavigationBar) {
        bar.isTranslucent = false
        bar.barStyle = .default
        bar.tintColor = YT6.titleBarText
        bar.setBackgroundImage(YT6.stretchableImage("titlebar"), for: .any, barMetrics: .default)
        bar.shadowImage = UIImage()
        bar.titleTextAttributes = [
            .font: YT6.xLargeLightFont,
            .foregroundColor: YT6.titleBarText
        ]
        // The 2.0.0 back button is a drawn plate, not iOS 7's chevron.
        let empty = UIImage()
        bar.backIndicatorImage = empty
        bar.backIndicatorTransitionMaskImage = empty
        let back = UIBarButtonItem.appearance(whenContainedInInstancesOf: [UINavigationBar.self])
        back.setBackButtonBackgroundImage(
            YT6.stretchableImage("back_button"), for: .normal, barMetrics: .default
        )
        back.setTitleTextAttributes(
            [.font: YT6.smallLightFont, .foregroundColor: YT6.titleBarText], for: .normal
        )
    }

    /// Replaces `ToolbarManager.install(in:)`: 2.0.0 has no bell, gear or
    /// avatar in the bar (account and settings live in the guide). Pushed
    /// screens keep the back button and get search on the right.
    static func replacesToolbar(in vc: UIViewController) -> Bool {
        guard YT6.isEnabled else {
            return false
        }
        if decorate(vc) {
            return true
        }
        vc.navigationItem.rightBarButtonItems = [searchButton(for: vc)]
        return true
    }

    /// `navSearchImage` → the 2.0.0 search bar over this screen (`YT6Search`).
    static func searchButton(for vc: UIViewController) -> UIBarButtonItem {
        let button = UIBarButtonItem(
            image: YT6.image("search"),
            style: .plain,
            target: vc,
            action: #selector(UIViewController.yt6OpenSearch)
        )
        button.accessibilityLabel = YT6.string("nav_bar.search.access", fallback: "Search")
        return button
    }

    /// Root screens of guide rows: guide button left, search right, and the
    /// row's title (the logo on What To Watch). Returns false for any other
    /// screen so upstream's own buttons stay.
    @discardableResult
    static func decorate(_ vc: UIViewController) -> Bool {
        guard let section = vc.yt6Section else {
            return false
        }
        vc.navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: YT6.image("guide"),
            style: .plain,
            target: YT6GuideActions.shared,
            action: #selector(YT6GuideActions.toggleGuide)
        )
        vc.navigationItem.rightBarButtonItems = [searchButton(for: vc)]
        // APPROXIMATION: logo as the title of What To Watch, the row title
        // elsewhere — to be checked against 2013 screenshots.
        if section == .whatToWatch, let logo = YT6.image("logo") {
            vc.navigationItem.titleView = UIImageView(image: logo)
        } else {
            vc.navigationItem.title = section.title
        }
        return true
    }
}

/// Target for the guide button: finds the window's root container.
final class YT6GuideActions: NSObject {
    static let shared = YT6GuideActions()

    @objc
    func toggleGuide() {
        let window = UIApplication.shared.keyWindow
        (window?.rootViewController as? RootContainerViewController)?.yt6Guide?.toggle()
    }
}
