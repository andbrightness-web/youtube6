import Foundation

/// Logs where the time goes on googlevideo requests (REQUEST685): DNS,
/// connect, TLS, wait for the first byte, whether the connection was reused
/// and whether it went through a proxy.
final class YT6NetMetrics: NSObject, URLSessionTaskDelegate {
    static func line(for item: URLSessionTaskTransactionMetrics, host: String) -> String {
        func span(_ start: Date?, _ end: Date?) -> String {
            guard let start, let end else {
                return "-"
            }
            return String(format: "%.0f", end.timeIntervalSince(start) * 1_000)
        }
        let total = span(item.fetchStartDate, item.responseEndDate)
        return "net \(host): dns=\(span(item.domainLookupStartDate, item.domainLookupEndDate))"
            + " connect=\(span(item.connectStartDate, item.connectEndDate))"
            + " tls=\(span(item.secureConnectionStartDate, item.secureConnectionEndDate))"
            + " firstByte=\(span(item.requestStartDate, item.responseStartDate))"
            + " total=\(total)ms reused=\(item.isReusedConnection)"
            + " proxy=\(item.isProxyConnection) proto=\(item.networkProtocolName ?? "-")"
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didFinishCollecting metrics: URLSessionTaskMetrics
    ) {
        for item in metrics.transactionMetrics {
            AppLog.hls(Self.line(for: item, host: task.originalRequest?.url?.host ?? "?"))
        }
    }
}

/// googlevideo answers every request to a stream's own host with a redirect
/// to the server that holds it, and the first host drops the connection:
/// each segment paid a fresh connection through the device's proxy, some
/// of them the ~5 s stall (REQUEST700, log 11:27:58: connect 4243 ms, then
/// the redirected transaction on a warm one). The final address is kept
/// per stream and used from then on; a failure there forgets it.
extension YT6NetMetrics {
    private static var redirects: [URL: URL] = [:]
    private static let redirectLock = NSLock()

    /// Where to send a request for `url`: its last redirect, or itself.
    static func resolved(_ url: URL) -> URL {
        redirectLock.lock()
        defer {
            redirectLock.unlock()
        }
        return redirects[url] ?? url
    }

    static func forget(_ url: URL) {
        redirectLock.lock()
        redirects.removeValue(forKey: url)
        redirectLock.unlock()
    }

    // swiftlint:disable:next function_parameter_count
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let from = task.originalRequest?.url, let to = request.url {
            Self.redirectLock.lock()
            // A resolved address can redirect again: update the stream it
            // stands for, not just itself.
            let origin = Self.redirects.first { $0.value == from }?.key ?? from
            let known = Self.redirects[origin] != nil
            Self.redirects[origin] = to
            Self.redirectLock.unlock()
            if !known {
                AppLog.hls("[Speed] redirect \(from.host ?? "?") → \(to.host ?? "?")")
            }
        }
        completionHandler(request)
    }
}

/// Bytes of streamed segments (`YT6SegmentStream`) as they arrive. Tasks
/// made with a completion handler never reach these.
extension YT6NetMetrics: URLSessionDataDelegate {
    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        YT6SegmentStream.stream(for: dataTask)?.receive(response: response)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        YT6SegmentStream.stream(for: dataTask)?.receive(data)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        YT6SegmentStream.stream(for: task)?.complete(error: error)
    }
}

extension YT6 {
    /// Session for googlevideo byte-range requests: `URLSession.shared`
    /// upstream; here the same configuration with timing logged.
    static let mediaSession: URLSession = makeMediaSession()

    /// One connection per googlevideo host: the identity probe, both index
    /// requests and the segments share a single warm connection. Each new
    /// connection through the device's proxy risked a ~5.3 s stall
    /// (REQUEST687, log 22:42–22:43: 6–9 new connections per video).
    private static var mediaConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 1
        return config
    }

    /// The session for one googlevideo URL. Video and audio split across
    /// two sessions doubled the new connections per video, and each new one
    /// through the device's proxy risked the ~5.3 s stall: start went from
    /// a 4.7 s median to 7.4–15.5 s (REQUEST698, log 21.10 11:08–11:13).
    /// Everything shares one warm connection again; the audio wait it
    /// brings is what streaming and seek cancelling now cut down.
    static func mediaSession(for _: URL) -> URLSession {
        mediaSession
    }

    /// The address to request a googlevideo stream at (see
    /// `YT6NetMetrics.resolved`); upstream asks the stream's own URL.
    static func mediaURL(for url: URL) -> URL {
        isEnabled ? YT6NetMetrics.resolved(url) : url
    }

    private static func makeMediaSession() -> URLSession {
        isEnabled
            ? URLSession(
                configuration: mediaConfiguration,
                delegate: YT6NetMetrics(),
                delegateQueue: nil
            )
            : .shared
    }
}
