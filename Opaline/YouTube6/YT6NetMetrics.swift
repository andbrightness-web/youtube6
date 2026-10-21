import Foundation

/// Logs where the time goes on googlevideo requests (REQUEST685): DNS,
/// connect, TLS, wait for the first byte, whether the connection was reused
/// and whether it went through a proxy.
final class YT6NetMetrics: NSObject, URLSessionTaskDelegate {
    private static func line(for item: URLSessionTaskTransactionMetrics, host: String) -> String {
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

extension YT6 {
    /// Session for googlevideo byte-range requests: `URLSession.shared`
    /// upstream; here the same configuration with timing logged. Video and
    /// audio each get one: on a shared single connection the 161 KB audio
    /// segment waited behind multi-megabyte video ones, up to 13.4 s
    /// (REQUEST695, research/YOUTUBE6-SPEED-2026-10-21.md).
    static let mediaSession: URLSession = makeMediaSession()
    static let audioMediaSession: URLSession = makeMediaSession()

    /// One connection per googlevideo host and session: the probe and the
    /// audio index share the audio one, the video index and segments the
    /// video one. Each new
    /// connection through the device's proxy risked a ~5.3 s stall
    /// (REQUEST687, log 22:42–22:43: 6–9 new connections per video).
    private static var mediaConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 1
        return config
    }

    /// The session for one googlevideo URL — audio streams say
    /// `mime=audio%2F…` in their query.
    static func mediaSession(for url: URL) -> URLSession {
        url.query?.contains("mime=audio") == true ? audioMediaSession : mediaSession
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
