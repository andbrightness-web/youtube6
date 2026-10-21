import UIKit

extension YT6AndCast {
    /// From `application(_:didFinishLaunchingWithOptions:)`: the address
    /// watch, the saved catalog and its polls, the queued watch reports.
    static func start() {
        log(
            "start: \(YT6Source.mode.title), "
                + (session.map { "signed in as \($0.user)" } ?? "not signed in")
        )
        YT6AndCastReach.startMonitoring()
        YT6AndCastCatalog.shared.start()
        let center = NotificationCenter.default
        let names = [
            UIApplication.willEnterForegroundNotification,
            YT6AndCastReach.didChangeNotification,
            YT6Source.didChangeNotification
        ]
        for name in names {
            center.addObserver(forName: name, object: nil, queue: .main) { _ in
                YT6AndCastStats.shared.flushPending()
                YT6AndCastJournal.flush()
                YT6AndCastCatalog.shared.sync()
            }
        }
        center.addObserver(forName: didChangeNotification, object: nil, queue: .main) { _ in
            YT6AndCastCatalog.shared.sync()
        }
    }

    /// A new source mode reaches every screen: the main interface is built
    /// again on the services of that mode, as after a sign-in
    /// (`AppDelegate.makeMain`). Whatever was playing stops.
    static func rebuildScreens() {
        guard let window = UIApplication.shared.delegate?.window.flatMap({ $0 }) else {
            return
        }
        log("screens rebuilt for \(YT6Source.mode.title)")
        window.rootViewController = RootContainerViewController(
            mainTabBar: MainTabBarController(dependencies: AppDependencies.live())
        )
    }
}
