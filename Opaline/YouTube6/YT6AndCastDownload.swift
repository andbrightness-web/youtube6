import Foundation

/// «Save to iPod» from andCast when the server has the video (REQUEST722,
/// 729, 731): the andCast client's device copy (`ACDownloads.m`) through
/// `YT6AndCastJobs` (one kept job per video, picked up again later), the
/// file in parallel ranges (`YT6AndCastFileFetch`), size and sha256
/// checked, then `POST /v1/downloads/{key}/delivered`. The stages show in
/// the row's grey line as the andCast client words them. Everything else —
/// the queue, `YT6DownloadBar`, the Downloads list, the storage — is
/// upstream's `VideoDownloader`, so a saved copy is a saved video.
enum YT6AndCastDownload {
    /// Marks an option as andCast's in `DownloadOption.video.itag`.
    static let itag = -722
    static let heights = [1_080, 720, 480, 360]

    /// The quality a copy is prepared at when nobody picked one (playback):
    /// the download setting's, else 720p — the same job a later «Save to
    /// iPod» at that setting picks up.
    static var preferredQuality: Int {
        let wanted = DownloadPreferences.preferredHeight ?? 720
        return heights.first { $0 <= wanted } ?? 360
    }

    /// andCast's renditions for this video, nil when YouTube should save it.
    static func options(
        for videoId: String,
        completion: @escaping (Result<[DownloadOption], Error>?) -> Void
    ) {
        let item = YT6AndCastCatalog.shared.item(videoId: videoId)
        switch YT6Source.mode {
        case .downloadedOnly:
            let why = "Downloaded only: nothing is fetched."
            completion(.failure(YT6AndCastError.unavailable(why)))
            return
        case .andCastOnly where item == nil:
            completion(.failure(YT6AndCastError.unavailable("This video is not on andCast.")))
            return
        case .youtubeAndCast where item == nil || !YT6AndCast.isSignedIn:
            completion(nil)
            return
        default:
            break
        }
        YT6AndCastReach.current { base in
            guard let item, base != nil else {
                YT6AndCast.log("save \(videoId): server not reachable")
                let refused = YT6AndCastError.unavailable("andCast is not reachable.")
                completion(YT6Source.mode == .andCastOnly ? .failure(refused) : nil)
                return
            }
            YT6AndCast.log("save \(videoId): from andCast (\(item.id))")
            completion(.success(heights.map { option(item: item, height: $0) }))
        }
    }

    static func isAndCast(_ option: DownloadOption) -> Bool {
        option.video.itag == itag
    }

    /// APPROXIMATION: sizes are estimates (the server says the real size
    /// only once the copy is ready): ~0.8/1.4/2.8/5 Mbit/s plus 128k audio.
    private static func option(item: YT6AndCastCatalog.Item, height: Int) -> DownloadOption {
        let rates = [1_080: 5_000_000, 720: 2_800_000, 480: 1_400_000, 360: 800_000]
        let bits = Double((rates[height] ?? 1_400_000) + 128_000)
        let bytes = Int64((item.seconds ?? 600) * bits / 8)
        let video = format(item: item, height: height, bytes: bytes)
        let audio = format(item: item, height: 0, bytes: 0)
        let label = "\(height)p · andCast"
        return DownloadOption(label: label, height: height, video: video, audio: audio)
    }

    private static func format(
        item: YT6AndCastCatalog.Item,
        height: Int,
        bytes: Int64
    ) -> DashFormatInfo {
        DashFormatInfo(
            url: URL(fileURLWithPath: "/andcast/\(item.id)"),
            itag: itag,
            mimeType: "video/mp4",
            codecs: "avc1",
            bitrate: 0,
            contentLength: bytes,
            initRangeEnd: 0,
            indexRangeStart: 0,
            indexRangeEnd: 0,
            width: nil,
            height: height,
            fps: nil,
            qualityLabel: "\(height)p",
            sigChallenge: nil,
            sigParam: nil,
            approxDurationMs: item.seconds.map { Int($0 * 1_000) },
            lastModified: nil,
            audioTrackId: nil,
            audioTrackName: nil,
            audioIsDefault: false,
            xtags: nil
        )
    }

    /// The andCast item an option was made for.
    static func item(of option: DownloadOption) -> String {
        option.video.url.lastPathComponent
    }

    /// The owner cancelled a save (or deleted it before it arrived): the
    /// server may drop the copy (`release`), the parts go.
    static func cancelled(_ videoId: String) {
        YT6AndCastJobs.setStage(nil, videoId: videoId)
        guard let item = YT6AndCastCatalog.shared.item(videoId: videoId) else {
            return
        }
        YT6AndCastJobs.release(item: item.id)
    }
}
