import Foundation

/// How a SABR segment the player asked for is fetched: the init from the
/// bytes the session opened with, the first segment of a start or a seek
/// with a second request when it is slow, everything else as upstream.
///
/// The first media segments of tv.sabr opens took 0.2–4.2 s for the same
/// sizes (log 21.10 12:51:51: 137/1 576 KB once in 192 ms, once in 4160 ms),
/// the slow ones being the new-connection stalls `YT6SABRSpeed` describes.
extension SABRDelivery {
    static func yt6Fetch(
        _ request: SABRSegmentRequest,
        of track: Track,
        route: Route,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard YT6.isEnabled else {
            route.fetcher.fetch(request, completion: completion)
            return
        }
        if request.isInit, let data = track.initData {
            completion(.success(data))
            return
        }
        guard let delay = YT6StartSegments.hedgeDelay(
            request, of: track, fetcher: route.fetcher
        ) else {
            route.fetcher.fetch(request, completion: completion)
            return
        }
        YT6SABRSpeed.fetchHedged(request, with: route.fetcher, after: delay, completion: completion)
    }
}

/// Which media segments are worth a second request: the first one of a
/// track and the first after a jump (a seek), where the player is waiting
/// with nothing on screen. Segments in sequence are buffering ahead and
/// can take their time.
enum YT6StartSegments {
    /// APPROXIMATION: a request this slow is a stalled connection rather
    /// than a big segment — 1.5 s for the first byte plus the size at
    /// 1 MB/s, the low end of the good transfers in the log.
    private static let firstByte: TimeInterval = 1.5
    private static let bytesPerSecond = 1_000_000.0

    private static var last: [String: Int] = [:]
    private static let lock = NSLock()

    static func hedgeDelay(
        _ request: SABRSegmentRequest,
        of track: SABRDelivery.Track,
        fetcher: SABRFetcher
    ) -> TimeInterval? {
        let index = request.sequence - 1
        let key = "\(ObjectIdentifier(fetcher).hashValue)/\(track.path)"
        lock.lock()
        if last.count > 64 {
            last.removeAll()
        }
        let previous = last[key]
        last[key] = index
        lock.unlock()
        guard previous.map({ index != $0 && index != $0 + 1 }) ?? true,
              track.segments.indices.contains(index) else {
            return nil
        }
        return firstByte + Double(track.segments[index].size) / bytesPerSecond
    }
}
