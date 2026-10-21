import UIKit

/// The andCast catalog on the iPod («базу я бы залил», REQUEST723).
///
/// Read like the andCast client's `fetchCatalog:` (`ACCatalog.m`): `GET
/// /andcast/v1/catalog` with `If-None-Match: "<revision>"` and `since=` so
/// an unchanged catalog costs a 304 and a changed one a delta (`delta`,
/// `base`, `removed`, changed `items`; `channels` always whole). Only what
/// youtube6 needs is kept, as a compact file: item id, YouTube id, title,
/// channel, date, length and artwork revision; channels with their avatar
/// revision and YouTube channel id. Descriptions are asked per video.
final class YT6AndCastCatalog {
    typealias Item = YT6AndCastItem
    typealias Channel = YT6AndCastChannel
    typealias Store = YT6AndCastStore

    static let shared = YT6AndCastCatalog()
    static let didChangeNotification = Notification.Name("YT6AndCastCatalogDidChange")
    private static let pollInterval: TimeInterval = 10 * 60

    static var account: String? {
        YT6AndCast.session.map { "\($0.server)|\($0.userID)" }
    }

    let queue = DispatchQueue(label: "yt6.andcast.catalog", qos: .utility)
    private let lock = NSLock()
    private var store: Store?
    private var byVideo: [String: Item] = [:]
    private var byItem: [String: Item] = [:]
    private var byChannel: [String: Channel] = [:]
    private(set) var isSyncing = false
    private(set) var lastSync: Date?
    private(set) var lastError: String?
    private var timer: Timer?

    private var file: URL {
        let manager = FileManager.default
        let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? manager.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("yt6-andcast-catalog.json")
    }

    /// Everything, newest first.
    var items: [Item] {
        lock.lock()
        defer { lock.unlock() }
        return store?.items ?? []
    }

    var channels: [Channel] {
        lock.lock()
        defer { lock.unlock() }
        return store?.channels ?? []
    }

    var revision: String? { currentStore?.revision }

    private var currentStore: Store? {
        lock.lock()
        defer { lock.unlock() }
        return store
    }

    // MARK: Lookups (any thread)

    func item(videoId: String) -> Item? {
        lock.lock()
        defer { lock.unlock() }
        return byVideo[videoId]
    }

    func item(andCastId id: String) -> Item? {
        lock.lock()
        defer { lock.unlock() }
        return byItem[id]
    }

    func channel(_ id: String?) -> Channel? {
        guard let id else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return byChannel[id]
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
                if let saved, saved.account == Self.account {
                    self.install(saved)
                    YT6AndCast.log("catalog: \(saved.items.count) videos from the saved copy")
                }
                self.sync()
            }
        }
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.pollInterval, repeats: true
        ) { [weak self] _ in
            if UIApplication.shared.applicationState == .active {
                self?.sync()
            }
        }
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

    // MARK: Sync

    /// One ETag poll; a no-op while one runs or nothing may be asked.
    func sync() {
        guard !isSyncing, YT6AndCast.isSignedIn, YT6Source.mode != .downloadedOnly else {
            return
        }
        isSyncing = true
        YT6AndCastReach.current { [weak self] base in
            guard let self else {
                return
            }
            guard let base, let request = self.catalogRequest(base: base) else {
                self.finishSync(error: "server not reachable")
                return
            }
            self.fetch(request)
        }
    }

    private func catalogRequest(base: URL) -> URLRequest? {
        let saved = currentStore
        let current = saved?.account == Self.account ? saved?.revision : nil
        var request = YT6AndCast.api(
            "v1/catalog", base: base, query: current.map { ["since": $0] } ?? [:]
        )
        if let current {
            request?.setValue("\"\(current)\"", forHTTPHeaderField: "If-None-Match")
        }
        request?.timeoutInterval = 60
        return request
    }

    private func fetch(_ request: URLRequest) {
        let started = Date()
        YT6AndCast.urlSession.dataTask(with: request) { [weak self] data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard let self else {
                return
            }
            guard error == nil, status == 200 || status == 304 else {
                YT6AndCastReach.noteFailure()
                DispatchQueue.main.async { self.finishSync(error: "HTTP \(status)") }
                return
            }
            let ms = Int(Date().timeIntervalSince(started) * 1_000)
            guard status == 200, let data else {
                YT6AndCast.log("catalog: unchanged (304) in \(ms) ms")
                DispatchQueue.main.async { self.finishSync(error: nil) }
                return
            }
            YT6AndCast.log("catalog: \(data.count / 1_024) KB in \(ms) ms")
            self.queue.async { self.apply(data) }
        }
        .resume()
    }

    /// Off the main queue: the whole catalog is tens of megabytes of JSON.
    private func apply(_ data: Data) {
        var next: Store?
        autoreleasepool {
            next = YT6AndCastCatalogParser.store(
                from: data, previous: currentStore, account: Self.account ?? ""
            )
        }
        guard let next else {
            DispatchQueue.main.async { self.finishSync(error: "unreadable catalog") }
            return
        }
        if let encoded = try? JSONEncoder().encode(next) {
            try? encoded.write(to: file, options: .atomic)
        }
        DispatchQueue.main.async {
            self.install(next)
            YT6AndCast.log(
                "catalog: \(next.items.count) videos, \(next.channels.count) channels,"
                    + " revision \(next.revision.prefix(8))"
            )
            self.finishSync(error: nil)
        }
    }

    private func install(_ next: Store?) {
        var videos: [String: Item] = [:]
        var ids: [String: Item] = [:]
        next?.items.forEach { item in
            videos[item.videoId] = item
            ids[item.id] = item
        }
        var channels: [String: Channel] = [:]
        next?.channels.forEach { channel in
            channels[channel.id] = channel
            if let youtube = channel.youtubeId {
                channels[youtube] = channel
            }
        }
        lock.lock()
        store = next
        byVideo = videos
        byItem = ids
        byChannel = channels
        lock.unlock()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    private func finishSync(error: String?) {
        isSyncing = false
        lastError = error
        if let error {
            YT6AndCast.log("catalog: sync failed, \(error)")
        } else {
            lastSync = Date()
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
