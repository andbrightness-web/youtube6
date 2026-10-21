import Foundation

/// Sends a watch kept in a local mode to YouTube with fresh tracking URLs:
/// the playback ping (adds the video to the account's watch history), then
/// one watchtime ping per watched range — the parameters
/// `WatchtimeTracker` uses (`ver=2`, `cpn`, `cmt`, `el=detailpage`,
/// `st`/`et`), under the account's bearer token.
enum YT6AndCastStatsReplay {
    static func send(_ watch: YT6AndCastStats.Watch, urls: WatchtimeURLs) {
        let cpn = PlaybackNonce.make()
        let start = watch.ranges.first?[0] ?? 0
        fire(urls.playbackURL, "ver=2&cpn=\(cpn)&cmt=\(fmt(start))&el=detailpage")
        for range in watch.ranges {
            let end = fmt(range[1])
            fire(
                urls.watchtimeURL,
                "ver=2&cpn=\(cpn)&cmt=\(end)&el=detailpage&st=\(fmt(range[0]))&et=\(end)"
            )
        }
        let when = Date(timeIntervalSince1970: watch.at)
        YT6AndCast.log(
            "stats: \(watch.videoId) sent to YouTube — watched \(Int(watch.watched)) s in"
                + " \(watch.ranges.count) ranges on \(when), history entry dated now"
        )
    }

    private static func fmt(_ seconds: Double) -> String {
        String(format: "%.3f", max(0, seconds))
    }

    private static func fire(_ base: String, _ extra: String) {
        let separator = base.contains("?") ? "&" : "?"
        guard let url = URL(string: base + separator + extra) else {
            return
        }
        OAuthClient.shared.validToken { result in
            var headers: [String: String] = [:]
            if case let .success(token) = result {
                headers[HTTPHeader.authorization] = "Bearer \(token)"
            }
            ServiceContainer.transport.send(
                HTTPRequest(method: .get, url: url, headers: headers),
                cancellationToken: nil
            ) { result in
                let code = (try? result.get().status) ?? 0
                YT6AndCast.log("stats: YouTube ping answered \(code)")
            }
        }
    }
}

/// andCast's viewing journal, as the andCast client keeps it: `watch`
/// events (`ACEvents watched:started:…`) through `POST /v1/operations`
/// with idempotent ids, queued while the server is away.
enum YT6AndCastJournal {
    private static let outboxKey = "yt6.andcast.outbox"
    private static var sending = false

    static func watched(item: String, watch: YT6AndCastStats.Watch) {
        let now = Date().timeIntervalSince1970
        let completed = watch.duration > 0 && watch.position >= watch.duration * 0.95
        let body: [String: Any] = [
            "v": 1, "type": "watch", "item": item, "at": now,
            "tz": TimeZone.current.secondsFromGMT() / 60, "started": min(watch.at, now),
            "watched": min(watch.watched, 86_400), "position": min(watch.position, 360_000),
            "duration": min(watch.duration, 360_000), "completed": completed,
            "source": "other", "audio": false
        ]
        let key = UUID().uuidString
        let operation: [String: Any] = ["id": key, "kind": "event", "key": key, "body": body]
        guard let data = try? JSONSerialization.data(withJSONObject: operation) else {
            return
        }
        var outbox = UserDefaults.standard.array(forKey: outboxKey) as? [Data] ?? []
        outbox.append(data)
        UserDefaults.standard.set(Array(outbox.suffix(500)), forKey: outboxKey)
        flush()
    }

    /// Sends up to 100 queued events; acked and rejected ones leave.
    static func flush() {
        let outbox = UserDefaults.standard.array(forKey: outboxKey) as? [Data] ?? []
        guard !sending, !outbox.isEmpty, YT6Source.mode != .downloadedOnly else {
            return
        }
        sending = true
        let batch = outbox.prefix(100).compactMap { try? JSONSerialization.jsonObject(with: $0) }
        YT6AndCast.call("v1/operations", body: ["operations": batch]) { reply in
            sending = false
            guard let reply else {
                return
            }
            let acked = reply["acked"] as? [String] ?? []
            let done = Set(acked + (reply["rejected"] as? [String] ?? []))
            let queued = UserDefaults.standard.array(forKey: outboxKey) as? [Data] ?? []
            let left = queued.filter { !done.contains(operationId($0) ?? "") }
            UserDefaults.standard.set(left, forKey: outboxKey)
            YT6AndCast.log("journal: \(done.count) watch events to andCast, \(left.count) queued")
        }
    }

    private static func operationId(_ data: Data) -> String? {
        let operation = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return operation?["id"] as? String
    }
}
