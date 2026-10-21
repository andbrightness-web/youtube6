import AVFoundation
import Foundation
import VideoToolbox

/// The andCast client's stream negotiation (`ACClient.m`
/// `preparePlayback:audio:position:forceHLS:`, `+deviceProfile`,
/// `+playbackChoice:`, `+mediaURL:server:`, `streamFor:source:`), ported.
enum YT6AndCastPlayback {
    struct Stream {
        var url: URL
        let method: String
        let session: String
        /// Sent with every media request (the prepared copy wants the token
        /// as `X-Emby-Token`; Jellyfin's URLs carry it themselves).
        var headers: [String: String] = [:]
        /// The source file's height; `tier` the transcode tier asked for
        /// (nil: the original or the prepared copy).
        var height: Int?
        var tier: Int?
        var isTranscode: Bool { method == "HLS" }

        var asset: AVURLAsset {
            let options = headers.isEmpty ? nil : ["AVURLAssetHTTPHeaderFieldsKey": headers]
            return AVURLAsset(url: url, options: options)
        }
    }

    private static let transcoding: [String: Any] = [
        "Type": "Video", "Container": "ts", "Protocol": "hls", "VideoCodec": "h264",
        "AudioCodec": "aac", "MaxAudioChannels": "2", "MinSegments": 1,
        "SegmentLength": 6, "BreakOnNonKeyFrames": false
    ]

    /// What the iPod decodes in hardware, as the andCast iPhone/TV client
    /// asks (`VTIsHardwareDecodeSupported`): H.264, and HEVC where there is
    /// a decoder (A9 and later). AV1 and VP9 never — those the server
    /// converts.
    static var videoCodecs: String {
        VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC) ? "h264,hevc" : "h264"
    }

    /// `+[ACClient deviceProfile]`: a conservative AVPlayer profile — H.264
    /// (and HEVC where decoded) up to 1080p, 8 bit, AAC/MP3 stereo; HLS/TS
    /// transcode for the rest. Never claims AV1/VP9. With a `tier` the size
    /// and bitrate conditions are that tier's: Jellyfin's StreamBuilder
    /// applies them to the transcode too, so a 1080p AV1 source no longer
    /// comes as 1080p at 6.3 Mbit/s (measured 21.10, REQUEST733).
    static func deviceProfile(tier: Int?) -> [String: Any] {
        let height = tier ?? 1_080
        var video: [[String: Any]] = [
            condition("LessThanEqual", "Width", "\(width(of: height))"),
            condition("LessThanEqual", "Height", "\(height)"),
            condition("LessThanEqual", "VideoBitDepth", "8"),
            // The A10 decodes High@4.2 (1080p60); 4.1 sent those to the transcoder.
            condition("LessThanEqual", "VideoLevel", "42"),
            condition("EqualsAny", "VideoProfile", "baseline|constrained baseline|main|high")
        ]
        if tier != nil {
            video.append(condition("LessThanEqual", "VideoBitrate", "\(bitrate(tier))"))
        }
        return [
            "Name": "andCast iOS 12",
            "MaxStreamingBitrate": bitrate(tier),
            "DirectPlayProfiles": [
                [
                    "Type": "Video", "Container": "mp4,m4v,mov",
                    "VideoCodec": videoCodecs, "AudioCodec": "aac,mp3"
                ]
            ],
            "TranscodingProfiles": [transcoding],
            "CodecProfiles": [
                ["Type": "Video", "Codec": "h264", "Conditions": video],
                [
                    "Type": "VideoAudio", "Codec": "aac,mp3",
                    "Conditions": [condition("LessThanEqual", "AudioChannels", "2")]
                ]
            ]
        ]
    }

    private static func condition(
        _ kind: String,
        _ property: String,
        _ value: String
    ) -> [String: Any] {
        ["Condition": kind, "Property": property, "Value": value, "IsRequired": true]
    }

    private static func playbackBody(user: String, tier: Int?) -> [String: Any] {
        [
            "UserId": user, "DeviceProfile": deviceProfile(tier: tier),
            "MaxStreamingBitrate": bitrate(tier), "MaxAudioChannels": 2,
            "EnableDirectPlay": tier == nil, "EnableDirectStream": tier == nil,
            "EnableTranscoding": true,
            "AllowVideoStreamCopy": true, "AllowAudioStreamCopy": true, "AutoOpenLiveStream": false
        ]
    }

    /// `PlaybackInfo`; `tier` (a height) asks Jellyfin for a transcode at
    /// that tier's bitrate instead of the best the iPod can take.
    static func negotiate(
        item: String,
        base: URL,
        tier: Int?,
        completion: @escaping (Result<Stream, Error>) -> Void
    ) {
        guard let session = YT6AndCast.session else {
            completion(.failure(YT6AndCastError.unavailable("not signed in")))
            return
        }
        let path = "Items/\(item)/PlaybackInfo"
        let body = playbackBody(user: session.userID, tier: tier)
        guard var request = YT6AndCast.jellyfin(path, base: base, body: body) else {
            completion(.failure(YT6AndCastError.unavailable("bad address")))
            return
        }
        request.timeoutInterval = 5
        YT6AndCast.perform(request) { result in
            completion(result.flatMap { data in
                let body = YT6AndCast.json(data) ?? [:]
                let found = stream(from: body, item: item, base: base, token: session.token)
                return found.map { at($0, tier: tier) }
            })
        }
    }

    /// The stream marked with its tier, a transcode capped to it.
    private static func at(_ found: Stream, tier: Int?) -> Stream {
        var chosen = found
        chosen.tier = tier
        if let tier, chosen.isTranscode {
            chosen.url = capped(chosen.url, tier: tier)
        }
        return chosen
    }

    /// `+playbackChoice:`: the first direct-playable source, else the first
    /// with a transcoding URL.
    private static func stream(
        from body: [String: Any],
        item: String,
        base: URL,
        token: String
    ) -> Result<Stream, Error> {
        let session = body["PlaySessionId"] as? String ?? ""
        let sources = body["MediaSources"] as? [[String: Any]] ?? []
        var fallback: Stream?
        for source in sources {
            guard let sid = source["Id"] as? String,
                  source["RequiresOpening"] as? Bool != true else {
                continue
            }
            let height = height(of: source)
            if source["SupportsDirectPlay"] as? Bool == true,
               let url = direct(item, sid, base, token) {
                let plain = Stream(
                    url: url, method: "Direct play", session: session, height: height
                )
                return .success(plain)
            }
            let hls = source["SupportsTranscoding"] as? Bool == true
                || source["SupportsDirectStream"] as? Bool == true
            if hls, fallback == nil, let path = source["TranscodingUrl"] as? String,
               let url = mediaURL(path, base: base) {
                fallback = Stream(url: url, method: "HLS", session: session, height: height)
                YT6AndCast.log("play \(item): Jellyfin converts — \(why(source, path: path))")
            }
        }
        guard let fallback else {
            return .failure(YT6AndCastError.unavailable("no stream the iPod can play"))
        }
        return .success(fallback)
    }

    /// `streamFor:source:` — Jellyfin takes the token in the URL for native
    /// media requests. Never logged.
    private static func direct(
        _ item: String,
        _ source: String,
        _ base: URL,
        _ token: String
    ) -> URL? {
        let stream = base.appendingPathComponent("Videos/\(item)/stream")
        var parts = URLComponents(url: stream, resolvingAgainstBaseURL: false)
        parts?.queryItems = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: source),
            URLQueryItem(name: "api_key", value: token)
        ]
        return parts?.url
    }

    /// `+mediaURL:server:` — a server-relative transcoding path, accepted
    /// only on the same scheme, host and port, below the server's path.
    private static func mediaURL(_ path: String, base: URL) -> URL? {
        guard !path.hasPrefix("//") else {
            return nil
        }
        let target: URL?
        if path.contains("://") {
            target = URL(string: path)
        } else {
            var relative = path.hasPrefix("/") ? String(path.dropFirst()) : path
            let prefix = base.path.isEmpty ? "" : String(base.path.dropFirst()) + "/"
            if !prefix.isEmpty, relative.hasPrefix(prefix) {
                relative = String(relative.dropFirst(prefix.count))
            }
            target = URL(string: base.absoluteString + "/" + relative)
        }
        guard let target, target.scheme == base.scheme, target.host == base.host,
              target.port == base.port, !target.path.contains(".."),
              target.path.hasPrefix(base.path + "/") || base.path.isEmpty else {
            return nil
        }
        return target
    }

    /// Why there is no direct play: the source's container and codecs and
    /// Jellyfin's `TranscodeReasons` (read off the URL; nothing else of it
    /// is logged).
    private static func why(_ source: [String: Any], path: String) -> String {
        let streams = source["MediaStreams"] as? [[String: Any]] ?? []
        let codec = { (kind: String) in
            streams.first { $0["Type"] as? String == kind }?["Codec"] as? String ?? "?"
        }
        let reasons = URLComponents(string: path)?.queryItems?
            .first { $0.name == "TranscodeReasons" }?.value ?? "none given"
        let container = source["Container"] as? String ?? "?"
        return "\(container) \(codec("Video"))/\(codec("Audio")), reasons \(reasons)"
    }

    /// `stopEncoding:` — `DELETE Videos/ActiveEncodings`.
    static func stopEncoding(_ session: String) {
        YT6AndCastReach.current { base in
            let query = ["deviceId": YT6AndCast.deviceId, "playSessionId": session]
            let path = "Videos/ActiveEncodings"
            guard let base, var request = YT6AndCast.jellyfin(path, base: base, query: query) else {
                return
            }
            request.httpMethod = "DELETE"
            YT6AndCast.perform(request) { _ in }
        }
    }
}
