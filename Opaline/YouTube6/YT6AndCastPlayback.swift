import Foundation

/// The andCast client's stream negotiation (`ACClient.m`
/// `preparePlayback:audio:position:forceHLS:`, `+deviceProfile`,
/// `+playbackChoice:`, `+mediaURL:server:`, `streamFor:source:`), ported.
enum YT6AndCastPlayback {
    struct Stream {
        let url: URL
        let method: String
        let session: String
        var isTranscode: Bool { method == "HLS" }
    }

    /// `+[ACClient deviceProfile]`: a conservative AVPlayer profile — H.264
    /// up to 1080p level 4.1, 8 bit, AAC/MP3 stereo; HLS/TS transcode for
    /// the rest. Never claims AV1/VP9/HEVC.
    static var deviceProfile: [String: Any] {
        let video: [[String: Any]] = [
            condition("LessThanEqual", "Width", "1920"),
            condition("LessThanEqual", "Height", "1080"),
            condition("LessThanEqual", "VideoBitDepth", "8"),
            condition("LessThanEqual", "VideoLevel", "41"),
            condition("EqualsAny", "VideoProfile", "baseline|constrained baseline|main|high")
        ]
        return [
            "Name": "andCast iOS 12",
            "MaxStreamingBitrate": 40_000_000,
            "DirectPlayProfiles": [
                [
                    "Type": "Video", "Container": "mp4,m4v,mov",
                    "VideoCodec": "h264", "AudioCodec": "aac,mp3"
                ]
            ],
            "TranscodingProfiles": [
                [
                    "Type": "Video", "Container": "ts", "Protocol": "hls", "VideoCodec": "h264",
                    "AudioCodec": "aac", "MaxAudioChannels": "2", "MinSegments": 1,
                    "SegmentLength": 6, "BreakOnNonKeyFrames": false
                ]
            ],
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

    static func resolve(
        item: String,
        base: URL,
        completion: @escaping (Result<Stream, Error>) -> Void
    ) {
        guard let session = YT6AndCast.session else {
            completion(.failure(YT6AndCastError.unavailable("not signed in")))
            return
        }
        let body: [String: Any] = [
            "UserId": session.userID, "DeviceProfile": deviceProfile,
            "MaxStreamingBitrate": 40_000_000, "MaxAudioChannels": 2,
            "EnableDirectPlay": true, "EnableDirectStream": true, "EnableTranscoding": true,
            "AllowVideoStreamCopy": true, "AllowAudioStreamCopy": true, "AutoOpenLiveStream": false
        ]
        let path = "Items/\(item)/PlaybackInfo"
        guard var request = YT6AndCast.jellyfin(path, base: base, body: body) else {
            completion(.failure(YT6AndCastError.unavailable("bad address")))
            return
        }
        request.timeoutInterval = 5
        YT6AndCast.perform(request) { result in
            completion(result.flatMap { data in
                let body = YT6AndCast.json(data) ?? [:]
                return stream(from: body, item: item, base: base, token: session.token)
            })
        }
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
            if source["SupportsDirectPlay"] as? Bool == true,
               let url = direct(item, sid, base, token) {
                return .success(Stream(url: url, method: "Direct play", session: session))
            }
            let hls = source["SupportsTranscoding"] as? Bool == true
                || source["SupportsDirectStream"] as? Bool == true
            if hls, fallback == nil, let path = source["TranscodingUrl"] as? String,
               let url = mediaURL(path, base: base) {
                fallback = Stream(url: url, method: "HLS", session: session)
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
