import Foundation

/// What a video needs before its first media byte, kept in memory: the
/// `/player` answer per client, the solved `n` of its stream URL and the
/// init segments (`ftyp/moov/sidx`) of its formats (step 2 of
/// research/YOUTUBE6-SPEED-2026-10-21.md). A second open of the same video —
/// back, a repeat, the next video warmed by `YT6Preload` — skips `/player`,
/// the solver round trip and both init requests: 0.6–3 s on tv.sabr in the
/// log 21.10 12:07–13:03 (7XXArSabyyA was opened five times that hour).
///
/// An answer lives until 20 minutes before the `expire` its stream URL
/// carries; a failure on it, at start or mid-playback, drops it.
enum YT6PlaybackCache {
    private struct Entry {
        let info: DirectPlaybackInfo
        let until: Date
    }

    /// APPROXIMATION: room for a session's worth of videos; init segments
    /// are 2–22 KB each in the log.
    private static let limit = 24
    private static let margin: TimeInterval = 20 * 60
    private static let fallbackLife: TimeInterval = 30 * 60

    private static var infos: [String: Entry] = [:]
    private static var solved: [String: String] = [:]
    private static var inits: [String: Data] = [:]
    private static let lock = NSLock()

    private static func key(_ videoId: String, _ client: String) -> String {
        "\(client)/\(videoId)"
    }

    private static func expiry(of info: DirectPlaybackInfo) -> Date {
        let url = info.serverAbrStreamingURL ?? info.videoURL ?? info.progressiveURL
        let expire = url
            .flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first { $0.name == "expire" }?.value
            .flatMap(TimeInterval.init)
        guard let expire else {
            return Date().addingTimeInterval(fallbackLife)
        }
        return Date(timeIntervalSince1970: expire - margin)
    }

    private static func locked<T>(_ work: () -> T) -> T {
        lock.lock()
        defer {
            lock.unlock()
        }
        return work()
    }

    static func info(videoId: String, client: String) -> DirectPlaybackInfo? {
        locked {
            guard let entry = infos[key(videoId, client)], entry.until > Date() else {
                return nil
            }
            return entry.info
        }
    }

    static func store(_ info: DirectPlaybackInfo, videoId: String, client: String) {
        let until = expiry(of: info)
        guard until > Date() else {
            return
        }
        locked {
            infos[key(videoId, client)] = Entry(info: info, until: until)
            let oldest = infos.min { $0.value.until < $1.value.until }
            if infos.count > limit, let oldest {
                infos.removeValue(forKey: oldest.key)
            }
        }
    }

    /// A start or a playback on this video failed: its answers may be what
    /// failed, so the next attempt asks again. Solved `n` values and init
    /// segments are not filed by video and go whole; they are cheap.
    static func forget(videoId: String) {
        locked {
            let gone = infos.keys.filter { $0.hasSuffix("/\(videoId)") }
            gone.forEach { infos.removeValue(forKey: $0) }
            solved.removeAll()
            inits.removeAll()
        }
    }

    static func solvedN(for unsolved: String) -> String? {
        locked { solved[unsolved] }
    }

    static func storeSolvedN(_ value: String, for unsolved: String) {
        locked {
            if solved.count > limit {
                solved.removeAll()
            }
            solved[unsolved] = value
        }
    }

    /// A format is named by its itag and the moment it was encoded, as the
    /// stream server names it; xtags tell dubs of one itag apart.
    private static func initKey(_ format: SabrFormatInfo) -> String {
        "\(format.itag)/\(format.lastModified ?? "-")/\(format.xtags ?? "-")"
    }

    static func initData(for format: SabrFormatInfo) -> Data? {
        locked { inits[initKey(format)] }
    }

    static func storeInit(_ data: Data, for format: SabrFormatInfo) {
        locked {
            if inits.count > limit * 2 {
                inits.removeAll()
            }
            inits[initKey(format)] = data
        }
    }
}

extension InnertubeVideoSource {
    /// `/player` for this source's client, from the cache when it holds a
    /// live answer; a fresh answer is kept for the next open.
    func yt6FetchDirectPlayback(
        _ videoId: String,
        _ poToken: String?,
        _ cancellation: CancellationToken?,
        _ completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void
    ) {
        let clientName = client.name
        if let cached = YT6PlaybackCache.info(videoId: videoId, client: clientName) {
            AppLog.player("[Speed] /player \(clientName) \(videoId) from cache")
            completion(.success(cached))
            return
        }
        apiClient.fetchDirectPlayback(
            videoId: videoId,
            client: client,
            poToken: poToken,
            cancellationToken: cancellation
        ) { result in
            if case .success(let info) = result {
                YT6PlaybackCache.store(info, videoId: videoId, client: clientName)
            }
            completion(result)
        }
    }
}
