import Network
import UIKit

/// Which andCast address answers (REQUEST722): the home address first, then
/// the public domain, each with a 1.5 s budget on `/andcast/v1/health`
/// (anonymous). The verdict is kept for a minute and asked again when the
/// network changes or the app comes back to the front. Nothing is probed
/// in «Downloaded only».
enum YT6AndCastReach {
    enum Place: Int {
        case home = 0
        case internet = 1

        var title: String { self == .home ? "Home" : "Internet" }
    }

    static let didChangeNotification = Notification.Name("YT6AndCastReachDidChange")
    private static let budget: TimeInterval = 1.5
    private static let freshFor: TimeInterval = 60

    private(set) static var base: URL?
    private(set) static var place: Place?
    private(set) static var isChecking = false
    private static var checkedAt: Date?
    private static var waiters: [(URL?) -> Void] = []
    private static var monitor: NWPathMonitor?

    private static let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = budget
        config.timeoutIntervalForResource = budget
        config.httpShouldSetCookies = false
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static var candidates: [(Place, URL)] {
        var list: [(Place, URL)] = []
        if let home = YT6AndCast.homeAddress.flatMap(URL.init(string:)) {
            list.append((.home, home))
        }
        if let server = YT6AndCast.session.flatMap({ URL(string: $0.server) }),
           !list.contains(where: { $0.1 == server }) {
            list.append((.internet, server))
        }
        return list
    }

    /// The address to use now; probes first when the verdict is stale.
    /// Calls back on the main queue.
    static func current(_ completion: @escaping (URL?) -> Void) {
        guard YT6AndCast.isSignedIn, YT6Source.mode != .downloadedOnly else {
            completion(nil)
            return
        }
        if let checkedAt, Date().timeIntervalSince(checkedAt) < freshFor {
            completion(base)
            return
        }
        waiters.append(completion)
        probeIfIdle()
    }

    /// Drops the verdict and asks again.
    static func refresh() {
        DispatchQueue.main.async {
            checkedAt = nil
            current { _ in }
        }
    }

    /// A request to `base` failed outright: ask again before the next one.
    static func noteFailure() {
        DispatchQueue.main.async { checkedAt = nil }
    }

    static func startMonitoring() {
        let path = NWPathMonitor()
        path.pathUpdateHandler = { _ in
            refresh()
        }
        path.start(queue: DispatchQueue(label: "yt6.andcast.path"))
        monitor = path
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            refresh()
        }
    }

    private static func probeIfIdle() {
        guard !isChecking else {
            return
        }
        isChecking = true
        probe(candidates, index: 0, started: Date())
    }

    private static func probe(_ list: [(Place, URL)], index: Int, started: Date) {
        guard index < list.count else {
            YT6AndCast.log("reach: no address answered in \(ms(since: started)) ms")
            finish(nil, place: nil)
            return
        }
        let (spot, url) = list[index]
        let health = url.appendingPathComponent("andcast/v1/health")
        let begun = Date()
        probeSession.dataTask(with: health) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let answered = status == 200 && data.flatMap(YT6AndCast.json)?["ok"] as? Bool == true
            DispatchQueue.main.async {
                let host = url.host ?? "?"
                guard answered else {
                    YT6AndCast.log("reach: \(spot.title.lowercased()) \(host) no (\(status))")
                    probe(list, index: index + 1, started: started)
                    return
                }
                YT6AndCast.log(
                    "reach: using \(spot.title.lowercased()) \(host), \(ms(since: begun)) ms"
                )
                finish(url, place: spot)
            }
        }
        .resume()
    }

    private static func finish(_ url: URL?, place found: Place?) {
        let changed = url != base
        base = url
        place = found
        checkedAt = Date()
        isChecking = false
        let callbacks = waiters
        waiters = []
        callbacks.forEach { $0(url) }
        if changed {
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    private static func ms(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1_000)
    }
}
