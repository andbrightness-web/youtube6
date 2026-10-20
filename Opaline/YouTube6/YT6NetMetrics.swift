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
    /// upstream; here the same configuration with timing logged.
    static let mediaSession: URLSession = isEnabled
        ? URLSession(configuration: .default, delegate: YT6NetMetrics(), delegateQueue: nil)
        : .shared
}
