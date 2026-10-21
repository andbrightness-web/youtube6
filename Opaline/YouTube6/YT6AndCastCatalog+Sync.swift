import UIKit

/// The server's sync signals, read as `ACCatalog fetchCatalog:` reads them.
extension YT6AndCastCatalog {
    /// `X-andCast-Refreshing` (the server scans: ask again in 5 s, as the
    /// andCast client does) and `X-andCast-Sync-Error`.
    func readFlags(_ headers: [AnyHashable: Any]) {
        let flag = { (name: String) in
            headers.first { ($0.key as? String)?.lowercased() == name }?.value as? String == "1"
        }
        serverRefreshing = flag("x-andcast-refreshing")
        if flag("x-andcast-sync-error") {
            lastError = "Could not check new videos. Your saved library is available."
        }
        if serverRefreshing {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.sync()
            }
        }
    }

    /// «Refresh»: `POST /v1/catalog/refresh`, then the catalog
    /// (`refresh:` of `ACCatalog`).
    func refreshNow() {
        YT6AndCast.call("v1/catalog/refresh", body: [String: Any]()) { [weak self] _ in
            self?.sync()
        }
    }

    // MARK: Life cycle

    /// Reads the saved copy, then keeps it fresh while the app is in front.
    func start() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            let saved = (try? Data(contentsOf: self.file))
                .flatMap { try? JSONDecoder().decode(Store.self, from: $0) }
            DispatchQueue.main.async {
                if let saved, saved.account == Self.account,
                   saved.version == Store.currentVersion {
                    self.install(saved)
                    YT6AndCast.log("catalog: \(saved.items.count) videos from the saved copy")
                }
                self.sync()
            }
        }
        YT6AndCastUpdates.start()
        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.sync()
        }
    }

    func reset() {
        install(nil)
        queue.async { [file] in
            try? FileManager.default.removeItem(at: file)
        }
    }

    func catalogRequest(base: URL) -> URLRequest? {
        let saved = currentStore
        let fresh = saved?.account == Self.account && saved?.version == Store.currentVersion
        let current = fresh ? saved?.revision : nil
        var request = YT6AndCast.api(
            "v1/catalog", base: base, query: current.map { ["since": $0] } ?? [:]
        )
        if let current {
            request?.setValue("\"\(current)\"", forHTTPHeaderField: "If-None-Match")
        }
        request?.timeoutInterval = 60
        return request
    }
}
