import UIKit

/// When the catalog is asked again — `listenUpdatesAfter:` of the andCast
/// client: `GET /v1/updates?catalog=<revision>&recommendations=…&tz=` is
/// held by the server up to 25 s and answers only when ready data changed
/// (204 = nothing, ask again at once); a new catalog revision starts a
/// sync, a new recommendations revision drops the Home shelf. Errors back
/// off 2 → 60 s; a server without `/updates` (404) is polled every 30 s.
/// Only while the app is in front.
enum YT6AndCastUpdates {
    private static var generation = 0
    private static var retry: TimeInterval = 2
    private static var recommendations = ""

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 40
        config.timeoutIntervalForResource = 45
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    static func start() {
        let center = NotificationCenter.default
        let active = UIApplication.didBecomeActiveNotification
        let away = UIApplication.didEnterBackgroundNotification
        center.addObserver(forName: active, object: nil, queue: .main) { _ in
            restart()
        }
        center.addObserver(forName: away, object: nil, queue: .main) { _ in
            generation += 1
        }
        restart()
    }

    private static func restart() {
        generation += 1
        retry = 2
        listen(after: 0, generation: generation)
    }

    private static func listen(after delay: TimeInterval, generation run: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard run == generation, YT6AndCast.isSignedIn, YT6Source.mode != .downloadedOnly else {
                return
            }
            YT6AndCastReach.current { base in
                let tz = TimeZone.current.secondsFromGMT() / 60
                let query = [
                    "catalog": YT6AndCastCatalog.shared.revision ?? "",
                    "recommendations": recommendations, "tz": "\(tz)"
                ]
                let request = base.flatMap { YT6AndCast.api("v1/updates", base: $0, query: query) }
                guard let request else {
                    listen(after: 30, generation: run)
                    return
                }
                session.dataTask(with: request) { data, response, error in
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    let body = status == 200 ? data.flatMap(YT6AndCast.json) : nil
                    DispatchQueue.main.async {
                        answered(status: error == nil ? status : 0, body: body, generation: run)
                    }
                }
                .resume()
            }
        }
    }

    private static func answered(status: Int, body: [String: Any]?, generation run: Int) {
        guard run == generation else {
            return
        }
        switch status {
        case 204:
            retry = 2
            listen(after: 0, generation: run)
        case 404:
            YT6AndCastCatalog.shared.sync()
            listen(after: 30, generation: run)
        case 200:
            let catalog = body?["catalog"] as? String
            recommendations = body?["recommendations"] as? String ?? recommendations
            let catalogs = YT6AndCastCatalog.shared
            guard catalog != catalogs.revision else {
                listen(after: 0, generation: run)
                return
            }
            // A failed sync is not retried every two seconds: a whole
            // catalog is tens of megabytes.
            let wait = catalogs.lastError == nil ? 2 : retry
            retry = catalogs.lastError == nil ? 2 : min(60, retry * 2)
            if !catalogs.isSyncing {
                YT6AndCast.log("updates: new catalog revision on the server")
                catalogs.sync()
            }
            listen(after: max(wait, 2), generation: run)
        default:
            let wait = retry
            retry = min(60, retry * 2)
            listen(after: wait, generation: run)
        }
    }
}
