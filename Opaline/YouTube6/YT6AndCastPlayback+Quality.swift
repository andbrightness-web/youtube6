import Foundation

/// Quality on andCast (REQUEST733): the original (direct play) or a ready
/// copy, and Jellyfin transcode tiers 1080/720/480/360 not above the
/// source. The start follows the app's Video Quality setting
/// (`VideoQualityStore.maxHeight`, «Auto» = up to 1080p), as for YouTube.
///
/// A source the iPod cannot decode (AV1, VP9 — most of the library) is
/// never «direct»: it is transcoded at the setting's tier, size-capped
/// (`MaxWidth`/`MaxHeight`) at a bitrate that suits the tier, so the HLS
/// variant's declared bandwidth matches its segments (the 1080p/6.3 Mbit/s
/// transcode of a 1.3 Mbit/s AV1 file gave CoreMedia -12318). Those are
/// the videos whose prepared device copy (REQUEST731) pays off.
///
/// APPROXIMATION: 4 / 2.5 / 1.2 / 0.7 Mbit/s for 1080/720/480/360.
extension YT6AndCastPlayback {
    static let tiers = [1_080, 720, 480, 360]

    static func bitrate(_ tier: Int?) -> Int {
        guard let tier else {
            return 40_000_000
        }
        return [1_080: 4_000_000, 720: 2_500_000, 480: 1_200_000][tier] ?? 700_000
    }

    /// 16:9 width of a tier.
    static func width(of height: Int) -> Int {
        [1_080: 1_920, 720: 1_280, 480: 854][height] ?? 640
    }

    /// The transcode URL with the tier's size cap, whatever Jellyfin wrote.
    static func capped(_ url: URL, tier: Int) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        let replaced = ["MaxHeight": "\(tier)", "MaxWidth": "\(width(of: tier))"]
        var items = (parts.queryItems ?? []).filter { replaced[$0.name] == nil }
        items += replaced.map { URLQueryItem(name: $0.key, value: $0.value) }
        parts.queryItems = items
        return parts.url ?? url
    }

    static func height(of source: [String: Any]) -> Int? {
        let streams = source["MediaStreams"] as? [[String: Any]] ?? []
        return streams.first { $0["Type"] as? String == "Video" }?["Height"] as? Int
    }

    /// A ready prepared copy at or below the setting first, then
    /// Jellyfin; a source above the setting comes as the setting's tier.
    static func resolve(
        item: String,
        base: URL,
        tier: Int?,
        completion: @escaping (Result<Stream, Error>) -> Void
    ) {
        if let tier {
            negotiate(item: item, base: base, tier: tier, completion: completion)
            return
        }
        let cap = VideoQualityStore.maxHeight ?? 1_080
        let settled: (Result<Stream, Error>) -> Void = { result in
            settle(result, item: item, base: base, cap: cap, completion: completion)
        }
        guard let job = YT6AndCastJobs.anyJob(item: item), job.quality <= cap,
              let token = YT6AndCast.session?.token else {
            negotiate(item: item, base: base, tier: nil, completion: settled)
            return
        }
        YT6AndCast.callStatus("v1/downloads/\(job.key)") { _, reply in
            guard reply?["status"] as? String == "ready" else {
                negotiate(item: item, base: base, tier: nil, completion: settled)
                return
            }
            completion(.success(copy(job, base: base, token: token)))
        }
    }

    // Direct within the setting plays as it is; anything else is asked
    // again at the tier it should be converted to.
    // swiftlint:disable:next function_parameter_count
    private static func settle(
        _ result: Result<Stream, Error>,
        item: String,
        base: URL,
        cap: Int,
        completion: @escaping (Result<Stream, Error>) -> Void
    ) {
        guard case .success(let stream) = result else {
            completion(result)
            return
        }
        let height = stream.height ?? cap
        guard stream.isTranscode || height > cap,
              let wanted = tiers.first(where: { $0 <= min(cap, height) }) else {
            completion(result)
            return
        }
        YT6AndCast.log("play \(item): source \(height)p, converting at \(wanted)p (cap \(cap)p)")
        negotiate(item: item, base: base, tier: wanted, completion: completion)
    }

    static func copy(_ job: YT6AndCastJobs.Job, base: URL, token: String) -> Stream {
        let file = base.appendingPathComponent("andcast/v1/downloads/\(job.key)/file")
        var stream = Stream(url: file, method: "prepared copy", session: "")
        stream.headers = ["X-Emby-Token": token]
        stream.height = job.quality
        return stream
    }
}
