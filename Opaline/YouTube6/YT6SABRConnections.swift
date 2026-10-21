import Foundation

/// Keeps SABR connections alive past the segment a request was about
/// (REQUEST721: «видео долго грузятся перематываются»).
///
/// Upstream stops a SABR response the moment its segment is complete by
/// cancelling the task. On HTTP/1.1 — every googlevideo transaction in the
/// log goes through the device's proxy as `proto=http/1.1` — a cancel with
/// body bytes still unread closes the connection, so the next request has to
/// open a new one, and new ones through the proxy are where the 3–16 s
/// stalls are. Log 21.10 13:56–14:54: 579 SABR `videoplayback`
/// transactions, 283 of them cut (`total=-ms`), 200 on a new connection
/// (`reused=false`) that cost 492 s of connect in all, 44 of them over 2 s
/// (14:34:06 `connect=15526`, 14:34:10 `connect=15393`, 14:34:18
/// `connect=15730`); reused ones answer in 0.1–0.3 s.
///
/// What is left after the segment is mostly a few hundred bytes: of 510
/// segments in the log, 456 had under 2 KB of the response past them when
/// they completed (`sabr 140/1@0ms -> 161900B of 162243B`). So the rest of
/// the response is read and dropped instead, and the connection goes back
/// to the pool; only a remainder over the budget is cancelled as before.
/// The segment itself still goes to the player at once.
enum YT6SABRConnections {
    private struct Drain {
        let host: String
        var bytes: Int64 = 0
    }

    /// APPROXIMATION: the most a response is read on past its segment —
    /// about a quarter of a second at the 2 MB/s of good transfers in the
    /// log, and above the 64–300 KB of the next segment that 15 of 510
    /// responses had already started when theirs completed.
    static let drainBudget: Int64 = 512 * 1_024
    /// APPROXIMATION: a remainder that has not arrived by then is a stalled
    /// response, and the connection is not worth waiting for.
    static let drainTimeout: TimeInterval = 4

    private static var drains: [ObjectIdentifier: Drain] = [:]
    private static let lock = NSLock()

    /// Called where upstream would cancel a finished SABR task: whether it is
    /// left to run out instead. False means cancel it as before.
    static func keep(_ task: URLSessionDataTask) -> Bool {
        let host = task.originalRequest?.url?.host ?? "?"
        guard host.hasSuffix("googlevideo.com") else {
            return false
        }
        let expected = task.countOfBytesExpectedToReceive
        let left = expected > 0 ? expected - task.countOfBytesReceived : 0
        guard left <= drainBudget else {
            YT6SABRStats.cut(host: host, after: 0, reason: "\(left) B left")
            return false
        }
        lock.lock()
        drains[ObjectIdentifier(task)] = Drain(host: host)
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + drainTimeout) {
            cut(task, reason: "not over in \(Int(drainTimeout)) s")
        }
        return true
    }

    /// Bytes of a task whose caller is done with it. Past the budget the
    /// connection is given up as upstream did.
    static func drained(_ task: URLSessionDataTask, bytes: Int) {
        lock.lock()
        guard var drain = drains[ObjectIdentifier(task)] else {
            lock.unlock()
            return
        }
        drain.bytes += Int64(bytes)
        drains[ObjectIdentifier(task)] = drain
        lock.unlock()
        if drain.bytes > drainBudget {
            cut(task, reason: "over \(drainBudget / 1_024) KB")
        }
    }

    /// The end of a task: a drained one that ran out on its own has left its
    /// connection in the pool.
    static func ended(_ task: URLSessionTask, error: Error?) {
        lock.lock()
        let drain = drains.removeValue(forKey: ObjectIdentifier(task))
        lock.unlock()
        guard let drain else {
            return
        }
        if error == nil {
            YT6SABRStats.kept(host: drain.host, drained: drain.bytes)
        } else {
            YT6SABRStats.cut(host: drain.host, after: drain.bytes, reason: "failed")
        }
    }

    private static func cut(_ task: URLSessionTask, reason: String) {
        lock.lock()
        let drain = drains.removeValue(forKey: ObjectIdentifier(task))
        lock.unlock()
        guard let drain else {
            return
        }
        YT6SABRStats.cut(host: drain.host, after: drain.bytes, reason: reason)
        task.cancel()
    }
}
