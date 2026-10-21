import UIKit

/// YouTube still hears about what is watched (REQUEST725).
///
/// «YouTube + andCast»: Opaline's own `WatchtimeTracker` runs for every
/// source — it fetches the `/player` tracking URLs under the account and
/// pings playback and watchtime with position, pauses and end — so a video
/// whose media comes from andCast reports exactly like a YouTube one.
///
/// «andCast only» reports to YouTube the same way when YouTube answers
/// (REQUEST727 allows YouTube's metadata there). When it does not, and in
/// «Downloaded only», what was watched (video, watched ranges, when) is
/// kept on the iPod and sent once YouTube can be reached again. Tracking URLs expire, so old
/// pings cannot be replayed honestly; fresh ones are fetched then, and the
/// video goes to the account's watch history at that moment with its
/// watched ranges (yt-dlp `--mark-watched`'s method). andCast's own journal
/// gets the watch as the andCast client sends it (`ACEvents watched:`).
final class YT6AndCastStats {
    struct Watch: Codable {
        let videoId: String
        let item: String?
        let at: Double
        let fromServer: Bool
        var ranges: [[Double]]
        var duration: Double
        var tries: Int

        var watched: Double { ranges.reduce(0) { $0 + max(0, $1[1] - $1[0]) } }
        var position: Double { ranges.last?[1] ?? 0 }
    }

    static let shared = YT6AndCastStats()
    private static let sampleEvery: TimeInterval = 5
    private static let pendingKey = "yt6.andcast.pendingWatches"
    private static let inflightKey = "yt6.andcast.inflightWatch"
    private static let maxPending = 300

    private weak var facade: PlaybackFacade?
    private var current: Watch?
    private var keepForYouTube = false
    private var timer: Timer?
    private var flushing = false

    private var pending: [Watch] {
        get { Self.read(Self.pendingKey, as: [Watch].self) ?? [] }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: Self.pendingKey)
        }
    }

    var pendingCount: Int { pending.count }

    /// The playback being watched now, for `YT6AndCastUpgrade`.
    var currentFacade: PlaybackFacade? { facade }

    private init() {
        if let left = Self.read(Self.inflightKey, as: Watch.self) {
            UserDefaults.standard.removeObject(forKey: Self.inflightKey)
            store(left, keep: true)
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.sample()
            self?.saveInflight()
        }
    }

    private static func read<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        let data = UserDefaults.standard.data(forKey: key)
        return data.flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    /// From `fetchWatchtimeAndTrack`: true when YouTube must not be asked.
    func begin(_ facade: PlaybackFacade) -> Bool {
        finish()
        guard let videoId = facade.currentVideoId else {
            return false
        }
        let server = (facade.activeVideoSource as? YT6AndCastSource)?.playingFromServer == true
        current = Watch(
            videoId: videoId,
            item: YT6AndCastCatalog.shared.item(videoId: videoId)?.id,
            at: Date().timeIntervalSince1970,
            fromServer: server,
            ranges: [],
            duration: 0,
            tries: 0
        )
        // «andCast only» tries YouTube first and keeps the watch only if it
        // does not answer (`youtubeAnswered`); offline always keeps it.
        keepForYouTube = YT6Source.isLocal
        self.facade = facade
        timer = Timer.scheduledTimer(
            withTimeInterval: Self.sampleEvery, repeats: true
        ) { [weak self] _ in
            self?.sample()
        }
        if YT6Source.mode == .downloadedOnly {
            YT6AndCast.log("stats: \(YT6Source.mode.title), \(videoId) kept for YouTube")
            return true
        }
        if server {
            YT6AndCast.log("stats: \(videoId) plays from andCast, YouTube watchtime as usual")
        }
        flushPending()
        return false
    }

    /// From the library's `fetchWatchtimeURLs` in «andCast only».
    func youtubeAnswered(videoId: String, reached: Bool) {
        DispatchQueue.main.async {
            guard self.current?.videoId == videoId else {
                return
            }
            self.keepForYouTube = !reached
            let how = reached ? "YouTube watchtime runs" : "YouTube unreachable, kept for later"
            YT6AndCast.log("stats: \(videoId) \(how)")
            if reached {
                self.flushPending()
            }
        }
    }

    private func sample() {
        guard var watch = current else {
            return
        }
        guard let facade, facade.currentVideoId == watch.videoId else {
            finish()
            return
        }
        let position = facade.watchtimeTracker.timeProvider?() ?? 0
        watch.duration = max(watch.duration, facade.watchtimeTracker.durationProvider?() ?? 0)
        let gap = Self.sampleEvery * 3
        if let last = watch.ranges.last, position >= last[0], position - last[1] <= gap {
            watch.ranges[watch.ranges.count - 1][1] = max(last[1], position)
        } else if position > 0 {
            watch.ranges.append([position, position])
        }
        current = watch
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        UserDefaults.standard.removeObject(forKey: Self.inflightKey)
        guard let watch = current else {
            return
        }
        current = nil
        store(watch, keep: keepForYouTube)
    }

    private func store(_ watch: Watch, keep: Bool) {
        guard watch.watched >= 1 else {
            return
        }
        if keep, !watch.videoId.hasPrefix("ac_") {
            var list = pending
            list.append(watch)
            pending = Array(list.suffix(Self.maxPending))
            YT6AndCast.log(
                "stats: \(watch.videoId) \(Int(watch.watched)) s kept, \(pending.count) for YouTube"
            )
        }
        if let item = watch.item, watch.fromServer || keep {
            YT6AndCastJournal.watched(item: item, watch: watch)
        }
    }

    private func saveInflight() {
        guard let current, let data = try? JSONEncoder().encode(current) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Self.inflightKey)
    }

    // MARK: YouTube, later

    /// One kept watch at a time, while the app talks to YouTube.
    func flushPending() {
        guard !flushing, YT6Source.mode != .downloadedOnly, OAuthClient.shared.isSignedIn,
              let first = pending.first else {
            return
        }
        flushing = true
        ServiceContainer.watch.fetchWatchtimeURLs(videoId: first.videoId) { [weak self] urls in
            DispatchQueue.main.async {
                self?.sent(first, urls: urls)
            }
        }
    }

    private func sent(_ watch: Watch, urls: WatchtimeURLs?) {
        flushing = false
        var list = pending
        let same = { (other: Watch) in other.videoId == watch.videoId && other.at == watch.at }
        guard let index = list.firstIndex(where: same) else {
            return
        }
        guard let urls else {
            list[index].tries += 1
            let dropped = list[index].tries >= 3
            let fate = dropped ? "dropped" : "kept"
            YT6AndCast.log("stats: no tracking for \(watch.videoId), \(fate)")
            if dropped {
                list.remove(at: index)
            }
            pending = list
            return
        }
        YT6AndCastStatsReplay.send(watch, urls: urls)
        list.remove(at: index)
        pending = list
        flushPending()
    }
}
