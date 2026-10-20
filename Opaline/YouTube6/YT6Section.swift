import UIKit

/// A guide row that shows a screen. Each one is a (hidden) tab of
/// `MainTabBarController`, so the player panel, the mini player and
/// `VideoRouter` keep working through the tab bar exactly as upstream.
///
/// Rows and icons follow `YTGuideTableView` (`cellForWhatToWatch`,
/// `cellForMySubscriptions`, `cellForAccountWatchLater`, …) and
/// `YTResources guide…ImageWithSelected:`; titles come from 2.0.0's
/// `Localizable.strings`.
enum YT6Section: Int, CaseIterable {
    case whatToWatch = 0
    case subscriptions = 1
    case watchLater = 2
    case history = 3
    case playlists = 4
    case liked = 5
    case live = 6
    case news = 7
    case gaming = 8
    case sports = 9
    case learning = 10
    case fashion = 11

    private struct Info {
        let key: String
        let fallback: String
        /// Base name of the `*_guide.png` icon (`_selected` alongside).
        let icon: String
        /// Account rows are hidden while signed out, as `YTGuideTableView`
        /// shows only "Sign In" then.
        var needsAccount = false
        /// A TV destination page shown by `HomeViewController`; its title is
        /// Opaline's (`key` is then an Opaline localization key).
        var browseId: String?

        init(_ key: String, _ fallback: String, _ icon: String, account: Bool) {
            self.key = key
            self.fallback = fallback
            self.icon = icon
            self.needsAccount = account
        }

        init(_ key: String, _ icon: String, destination: String) {
            self.key = key
            self.fallback = key
            self.icon = icon
            self.browseId = destination
        }
    }

    /// FROM YOUTUBE: Live and the categories (REQUEST682). 2.0.0 listed
    /// YouTube's categories here; today's TV destinations take their place.
    static let fromYouTube: [Self] = [.live, .news, .gaming, .sports, .learning, .fashion]

    private static let table: [Info] = [
        Info("guide.what_to_watch", "What To Watch", "what_to_watch_guide", account: false),
        Info("guide.subscriptions", "My Subscriptions", "subscriptions_guide", account: false),
        Info("account.watch_later", "Watch Later", "watch_later_guide", account: true),
        Info("account.watch_history", "History", "history_guide", account: true),
        Info("account.playlists", "Playlists", "playlists_guide", account: true),
        // 2.0.0 had Favorites here; YouTube has none now (REQUEST680).
        Info("", "Liked videos", "favorites_guide", account: true),
        Info("guide.live", "Live", "live_guide", account: false),
        Info("home.category.news", "news_guide", destination: BrowseID.newsDestination),
        Info("home.category.gaming", "games_guide", destination: BrowseID.gamingDestination),
        Info("home.category.sports", "sports_guide", destination: BrowseID.sportsDestination),
        Info(
            "home.category.learning",
            "education_guide",
            destination: BrowseID.learningDestination
        ),
        // 2.0.0's "Howto & Style" icon.
        Info("home.category.fashion", "howto_guide", destination: BrowseID.fashionDestination)
    ]

    private var info: Info { Self.table[rawValue] }

    var title: String {
        if self == .liked {
            return Locale.preferredLanguages.first?.hasPrefix("ru") == true
                ? "Понравившиеся"
                : info.fallback
        }
        if info.browseId != nil {
            return info.key.localized
        }
        return YT6.string(info.key, fallback: info.fallback)
    }

    var icon: String { info.icon }
    var needsAccount: Bool { info.needsAccount }

    func makeRoot(_ dependencies: AppDependencies) -> UIViewController {
        let channels = dependencies.makeChannelViewController
        switch self {
        case .whatToWatch, .live, .news, .gaming, .sports, .learning, .fashion:
            let home = HomeViewController(
                service: dependencies.feedService,
                channelViewControllerFactory: channels
            )
            home.yt6Destination = self == .live ? BrowseID.liveDestination : info.browseId
            return home
        case .subscriptions:
            return dependencies.makeSubscriptionsViewController()
        case .history:
            return HistoryViewController(
                service: dependencies.historyService,
                channelViewControllerFactory: channels
            )
        case .playlists:
            return PlaylistsViewController(
                service: dependencies.playlistService,
                channelViewControllerFactory: channels
            )
        case .watchLater, .liked:
            return makePlaylist(dependencies)
        }
    }

    private func makePlaylist(_ dependencies: AppDependencies) -> UIViewController {
        PlaylistVideosViewController(
            playlist: Playlist(
                id: self == .liked ? "LL" : "WL",
                title: title,
                description: "",
                thumbnailURL: nil,
                itemCount: nil
            ),
            service: dependencies.playlistService,
            channelViewControllerFactory: dependencies.makeChannelViewController
        )
    }
}

extension MainTabBarController {
    var yt6SelectedSection: YT6Section? {
        YT6Section(rawValue: selectedIndex)
    }

    /// Replaces the tab list: one navigation stack per guide row, tab bar
    /// hidden. Shorts are cut entirely (REQUEST680).
    func yt6BuildTabs() -> [UIViewController] {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.Feed.showShorts)
        tabBar.isHidden = true
        return YT6Section.allCases.map { section in
            let root = section.makeRoot(dependencies)
            root.yt6Section = section
            YT6Chrome.decorate(root)
            return RotatingNavigationController(rootViewController: root)
        }
    }

    func yt6Select(_ section: YT6Section) {
        guard let navs = viewControllers, navs.indices.contains(section.rawValue) else {
            return
        }
        if selectedIndex == section.rawValue,
           let nav = navs[section.rawValue] as? UINavigationController {
            if nav.viewControllers.count > 1 {
                nav.popToRootViewController(animated: false)
            } else if let scrollable = nav.topViewController as? ScrollableToTop {
                scrollable.scrollToTop()
            }
        }
        selectedIndex = section.rawValue
    }
}

private var yt6SectionKey: UInt8 = 0

extension UIViewController {
    /// The guide row this controller is the root screen of, if any.
    var yt6Section: YT6Section? {
        get {
            (objc_getAssociatedObject(self, &yt6SectionKey) as? Int).flatMap(YT6Section.init)
        }
        set {
            objc_setAssociatedObject(
                self, &yt6SectionKey, newValue?.rawValue, .OBJC_ASSOCIATION_RETAIN
            )
        }
    }
}
