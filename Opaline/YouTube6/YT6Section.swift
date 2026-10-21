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
    /// Downloads (REQUEST711): 2.0.0 had none; Opaline's downloads, shown
    /// as a 2013 list in the account group.
    case downloads = 12

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
        Info("home.category.fashion", "howto_guide", destination: BrowseID.fashionDestination),
        Info("", "Downloads", "downloads_guide", account: false)
    ]

    private var info: Info { Self.table[rawValue] }

    var title: String {
        if self == .liked || self == .downloads {
            let russian = self == .liked ? "Понравившиеся" : "Загрузки"
            return Locale.preferredLanguages.first?.hasPrefix("ru") == true
                ? russian
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
        case .downloads:
            return DownloadsViewController(channelViewControllerFactory: channels)
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
    /// One navigation stack per guide row, built once and kept so each row
    /// remembers its place. Only the selected one is ever a tab: a tab bar
    /// controller moves tabs past the fifth into its system "More" stack,
    /// whose own bar would show instead of the 2.0.0 one.
    private var yt6Stacks: [UIViewController] {
        get {
            objc_getAssociatedObject(self, &yt6StacksKey) as? [UIViewController] ?? []
        }
        set {
            objc_setAssociatedObject(self, &yt6StacksKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    var yt6SelectedSection: YT6Section? {
        guard let selected = selectedViewController else {
            return nil
        }
        return yt6Stacks.firstIndex { $0 === selected }.flatMap(YT6Section.init)
    }

    /// Replaces the tab list with the selected guide row; tab bar hidden.
    /// Shorts are cut entirely (REQUEST680).
    func yt6BuildTabs() -> [UIViewController] {
        UserDefaults.standard.set(false, forKey: UserDefaultsKeys.Feed.showShorts)
        // 2.0.0 feeds are lists: never TV-style shelf rails.
        let defaults = UserDefaults.standard
        defaults.set(HomeLayout.grid.rawValue, forKey: UserDefaultsKeys.Feed.homeLayout)
        // No auto-dub in 2013, and its probe cost a second stream build
        // (REQUEST685) — off unless chosen in Settings.
        if defaults.object(forKey: UserDefaultsKeys.AutoDub.enabled) == nil {
            defaults.set(false, forKey: UserDefaultsKeys.AutoDub.enabled)
        }
        tabBar.isHidden = true
        yt6Stacks = YT6Section.allCases.map { section in
            let root = section.makeRoot(dependencies)
            root.yt6Section = section
            YT6Chrome.decorate(root)
            return RotatingNavigationController(rootViewController: root)
        }
        return Array(yt6Stacks.prefix(1))
    }

    func yt6Select(_ section: YT6Section) {
        let stacks = yt6Stacks
        guard stacks.indices.contains(section.rawValue) else {
            return
        }
        let stack = stacks[section.rawValue]
        guard stack !== selectedViewController else {
            if let nav = stack as? UINavigationController, nav.viewControllers.count > 1 {
                nav.popToRootViewController(animated: false)
            } else if let nav = stack as? UINavigationController,
                      let scrollable = nav.topViewController as? ScrollableToTop {
                scrollable.scrollToTop()
            }
            return
        }
        setViewControllers([stack], animated: false)
    }
}

private var yt6StacksKey: UInt8 = 0
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
