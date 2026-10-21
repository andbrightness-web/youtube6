import Foundation
import QuartzCore

/// Start of a tv.sabr video (log 21.10 12:07–13:03, every open since VISIONOS
/// is bot-checked): the two init requests took 0.5–9.3 s, one never answered
/// in 12 s (12:51:21, the viewer gave up) and one failed after 5.4 s, which
/// sent the whole chain round again for +10 s (13:03:47). Every SABR request
/// ends with a cancel once its segment is in, and on HTTP/1.1 that closes
/// the connection: each one opens a new connection through the device's
/// proxy, the path with the ~5 s stalls (REQUEST687).
enum YT6SABRSpeed {
    /// A second init request goes out when the first has not answered by
    /// then, or at once when it fails. APPROXIMATION: good inits land in
    /// 0.5–1.7 s in the log; the stalled ones take 3.5 s and more.
    static let hedgeDelay: TimeInterval = 2.0

    /// Opens connections to the stream's host while the `n` challenge is
    /// solved, so the init requests find them warm. `generate_204` is the
    /// address googlevideo's own players warm a host with.
    static func warm(_ streamURL: URL, transport: HTTPTransport, connections: Int = 2) {
        guard let host = streamURL.host,
              let url = URL(string: "https://\(host)/generate_204") else {
            return
        }
        let request = HTTPRequest(
            method: .get, url: url, timeout: 10, sendsCookies: false, isPlayback: true
        )
        for _ in 0..<connections {
            transport.stream(
                request,
                cancellationToken: nil,
                onChunk: { _ in true },
                completion: { _ in }
            )
        }
    }

    /// One init segment, asked for a second time when the first request is
    /// slow or fails; whichever answers first wins.
    static func fetchInit(
        _ request: SABRSegmentRequest,
        with fetcher: SABRFetcher,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        fetchHedged(request, with: fetcher, after: hedgeDelay, completion: completion)
    }

    static func fetchHedged(
        _ request: SABRSegmentRequest,
        with fetcher: SABRFetcher,
        after delay: TimeInterval,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        let race = YT6SegmentRace(request: request, fetcher: fetcher, completion: completion)
        race.send(1)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + delay) {
            race.hedge(reason: "slow")
        }
    }
}

/// First answer of up to two identical SABR segment requests.
private final class YT6SegmentRace {
    private let request: SABRSegmentRequest
    private let fetcher: SABRFetcher
    private let completion: (Result<Data, Error>) -> Void
    private let started = CACurrentMediaTime()
    private let lock = NSLock()
    private var launched = 1
    private var failed = 0
    private var done = false

    private var label: String {
        "\(request.format.itag)/\(request.isInit ? "init" : "\(request.sequence)")"
    }

    private var elapsed: Int {
        Int((CACurrentMediaTime() - started) * 1_000)
    }

    init(
        request: SABRSegmentRequest,
        fetcher: SABRFetcher,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        self.request = request
        self.fetcher = fetcher
        self.completion = completion
    }

    func send(_ attempt: Int) {
        fetcher.fetch(request) { result in
            self.finish(result, attempt: attempt)
        }
    }

    /// Sends the second request unless the race is over or it already went.
    func hedge(reason: String) {
        lock.lock()
        guard !done, launched == 1 else {
            lock.unlock()
            return
        }
        launched = 2
        lock.unlock()
        AppLog.hls("[Speed] sabr \(label) \(reason) after \(elapsed) ms, asking again")
        send(2)
    }

    private func finish(_ result: Result<Data, Error>, attempt: Int) {
        lock.lock()
        guard !done else {
            lock.unlock()
            return
        }
        guard case .success = result else {
            failed += 1
            let retry = launched == 1
            done = !retry && failed == launched
            let report = done
            lock.unlock()
            if retry {
                hedge(reason: "failed")
            } else if report {
                completion(result)
            }
            return
        }
        done = true
        let total = launched
        lock.unlock()
        if request.isInit, case .success(let data) = result {
            YT6PlaybackCache.storeInit(data, for: request.format)
        }
        AppLog.hls("[Speed] sabr \(label) +\(elapsed) ms (request \(attempt) of \(total))")
        completion(result)
    }
}

/// Where the time of each SABR request goes, as `YT6NetMetrics` logs the
/// range requests: connect, first byte, reused or new connection.
extension StreamingSession {
    @objc(URLSession:task:didFinishCollectingMetrics:)
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        guard YT6.isEnabled else {
            return
        }
        for item in metrics.transactionMetrics {
            let host = item.request.url?.host ?? "?"
            guard host.hasSuffix("googlevideo.com") else {
                continue
            }
            let status = (item.response as? HTTPURLResponse)?.statusCode ?? 0
            let path = item.request.url?.lastPathComponent ?? ""
            YT6SABRStats.note(item, host: host)
            AppLog.hls("[Speed] sabr " + YT6NetMetrics.line(for: item, host: host)
                + " \(path) \(status)")
        }
    }
}
