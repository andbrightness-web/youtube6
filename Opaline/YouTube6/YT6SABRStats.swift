import Foundation

/// What one tv.sabr playback paid for connections, and the pings that keep
/// them open while it is paused or buffered ahead (REQUEST721).
///
/// The `[Speed] sabr connections` line is the proof `YT6SABRConnections`
/// works: SABR requests on a reused connection against new ones, the
/// connect time the new ones cost, how many responses ran out on their own
/// and how many were still cut. Logged every 20 requests and when the
/// playback is gone.
enum YT6SABRStats {
    private struct Weak {
        weak var object: AnyObject?
    }

    private final class Entry {
        let streamURL: URL
        let transport: HTTPTransport
        var owners: [Weak] = []
        var requests = 0
        var reused = 0
        var connectMs = 0
        var slowConnects = 0
        var waited = 0
        var kept = 0
        var drainedBytes: Int64 = 0
        var cut = 0
        var pings = 0
        var lastNet = Date()
        var lastSegment = Date()

        init(streamURL: URL, transport: HTTPTransport) {
            self.streamURL = streamURL
            self.transport = transport
        }
    }

    /// APPROXIMATION: an idle connection survived 51 and 71 s in the log
    /// (21.10 14:40:36, 14:42:41, `reused=true`); how much longer is not
    /// known, so one is pinged before that.
    private static let pingAfter: TimeInterval = 45
    /// APPROXIMATION: a paused video keeps its connections this long after
    /// its last segment; past that a cold start is the cheaper waste.
    private static let keepFor: TimeInterval = 5 * 60
    private static let tick: TimeInterval = 5
    private static let logEvery = 20
    /// A wait this long for a connection is the pool being full.
    private static let longWaitMs = 1_000

    private static var entries: [String: Entry] = [:]
    private static var timer: DispatchSourceTimer?
    private static let queue = DispatchQueue(label: "com.ytvlite.yt6.sabr-stats")

    /// A tv.sabr playback opening on its stream's host; `owner` is the
    /// delivery, and the host is looked after for as long as one is alive.
    static func begin(_ streamURL: URL, transport: HTTPTransport, owner: AnyObject) {
        guard let host = streamURL.host else {
            return
        }
        queue.async {
            let entry = entries[host] ?? Entry(streamURL: streamURL, transport: transport)
            entry.owners = entry.owners.filter { $0.object != nil } + [Weak(object: owner)]
            entry.lastSegment = Date()
            entries[host] = entry
            startTimer()
        }
    }

    /// One finished SABR transaction, from the session's metrics.
    static func note(_ item: URLSessionTaskTransactionMetrics, host: String) {
        let isSegment = item.request.url?.lastPathComponent == "videoplayback"
        let connect = item.connectStartDate.flatMap { start in
            item.connectEndDate.map { Int($0.timeIntervalSince(start) * 1_000) }
        }
        let wait = item.requestStartDate.map { start in
            Int(start.timeIntervalSince(item.fetchStartDate ?? start) * 1_000) - (connect ?? 0)
        }
        queue.async {
            guard let entry = entries[host] else {
                return
            }
            entry.lastNet = Date()
            guard isSegment else {
                return
            }
            entry.lastSegment = Date()
            entry.requests += 1
            entry.reused += item.isReusedConnection ? 1 : 0
            entry.connectMs += connect ?? 0
            entry.slowConnects += (connect ?? 0) > 2_000 ? 1 : 0
            entry.waited += (wait ?? 0) > longWaitMs ? 1 : 0
            if entry.requests.isMultiple(of: logEvery) {
                report(host, entry, closing: false)
            }
        }
    }

    static func kept(host: String, drained: Int64) {
        queue.async {
            entries[host]?.kept += 1
            entries[host]?.drainedBytes += drained
        }
    }

    static func cut(host: String, after bytes: Int64, reason: String) {
        AppLog.hls("[Speed] sabr \(host): cut after \(bytes) B (\(reason)), connection lost")
        queue.async {
            entries[host]?.cut += 1
        }
    }

    private static func report(_ host: String, _ entry: Entry, closing: Bool) {
        let fresh = entry.requests - entry.reused
        AppLog.hls(
            "[Speed] sabr connections \(host)\(closing ? " (closed)" : ""):"
                + " \(entry.requests) requests, \(entry.reused) reused, \(fresh) new"
                + " (connect \(entry.connectMs) ms, \(entry.slowConnects) over 2 s),"
                + " \(entry.waited) waited over 1 s for one,"
                + " \(entry.kept) ran out (\(entry.drainedBytes / 1_024) KB),"
                + " \(entry.cut) cut, \(entry.pings) pings"
        )
    }

    private static func startTimer() {
        guard timer == nil else {
            return
        }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + tick, repeating: tick)
        source.setEventHandler(handler: check)
        source.resume()
        timer = source
    }

    /// Pings hosts that have gone quiet under a live playback, and closes the
    /// books on those whose playback is gone.
    private static func check() {
        let now = Date()
        for (host, entry) in entries {
            guard entry.owners.contains(where: { $0.object != nil }) else {
                if entry.requests > 0 {
                    report(host, entry, closing: true)
                }
                entries.removeValue(forKey: host)
                continue
            }
            guard now.timeIntervalSince(entry.lastNet) >= pingAfter,
                  now.timeIntervalSince(entry.lastSegment) < keepFor else {
                continue
            }
            entry.pings += 1
            entry.lastNet = now
            AppLog.hls("[Speed] sabr \(host): keep-alive ping after \(Int(pingAfter)) s quiet")
            YT6SABRSpeed.warm(entry.streamURL, transport: entry.transport)
        }
        if entries.isEmpty {
            timer?.cancel()
            timer = nil
        }
    }
}
