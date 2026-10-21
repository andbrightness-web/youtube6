import Foundation

/// «Save to iPod» from andCast when the server has the video (REQUEST722):
/// the andCast client's device copy (`ACDownloads.m`) — `POST
/// /v1/downloads` {item, mode, quality, device}, `GET /v1/downloads/{key}`
/// until `ready` (the server remuxes or converts to H.264/AAC for the
/// iPod), the file from `/v1/downloads/{key}/file`, then `POST
/// /v1/downloads/{key}/delivered` with its sha256. Everything else — the
/// queue, `YT6DownloadBar`, the Downloads list, the storage — is upstream's
/// `VideoDownloader`, so a saved copy is a saved video like any other.
enum YT6AndCastDownload {
    /// Marks an option as andCast's in `DownloadOption.video.itag`.
    static let itag = -722
    static let heights = [1_080, 720, 480, 360]

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
}

extension VideoDownloader {
    /// `fetchTracks` for an andCast option: prepare on the server, wait,
    /// fetch the file into the video's folder, report it delivered.
    func yt6FetchFromAndCast(videoId: String, option: DownloadOption) {
        let item = YT6AndCastDownload.item(of: option)
        let body: [String: Any] = [
            "item": item, "mode": "video", "quality": option.height, "device": YT6AndCast.deviceId
        ]
        YT6AndCast.call("v1/downloads", body: body) { [weak self] reply in
            self?.yt6AndCastWait(videoId: videoId, option: option, job: reply, polls: 0)
        }
    }

    private func yt6AndCastWait(
        videoId: String,
        option: DownloadOption,
        job: [String: Any]?,
        polls: Int
    ) {
        guard cancellation?.isCancelled == false, activeVideoId == videoId else {
            return
        }
        guard let job, let key = job["key"] as? String, let status = job["status"] as? String else {
            fail(videoId: videoId, error: YT6AndCastError.unavailable("andCast refused the copy"))
            return
        }
        switch status {
        case "ready":
            yt6AndCastTransfer(videoId: videoId, option: option, job: job, key: key)
        case "queued", "preparing":
            if polls.isMultiple(of: 10) {
                let done = Int(((job["preparationProgress"] as? Double) ?? 0) * 100)
                YT6AndCast.log("save \(videoId): server is preparing the copy, \(done) %")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                YT6AndCast.call("v1/downloads/\(key)") { reply in
                    self?.yt6AndCastWait(
                        videoId: videoId, option: option, job: reply, polls: polls + 1
                    )
                }
            }
        default:
            let why = job["error"] as? String ?? status
            fail(videoId: videoId, error: YT6AndCastError.unavailable("andCast: \(why)"))
        }
    }

    private func yt6AndCastTransfer(
        videoId: String,
        option: DownloadOption,
        job: [String: Any],
        key: String
    ) {
        let bytes = (job["bytes"] as? Int64) ?? (job["bytes"] as? Int).map(Int64.init) ?? 0
        let path = job["path"] as? String ?? "v1/downloads/\(key)/file"
        YT6AndCast.log("save \(videoId): copy ready, \(bytes / 1_048_576) MB, fetching")
        YT6AndCastReach.current { [weak self] base in
            let relative = String(path.drop { $0 == "/" })
            guard let self, let base, let request = YT6AndCast.api(relative, base: base) else {
                let gone = YT6AndCastError.unavailable("andCast went away")
                self?.fail(videoId: videoId, error: gone)
                return
            }
            let scale = Double(max(option.bytes, 1)) / Double(max(bytes, 1))
            YT6AndCastFileFetch.start(request, scale: scale, downloader: self) { result in
                let sha = job["sha256"] as? String
                self.yt6AndCastFinish(videoId: videoId, key: key, sha: sha, result: result)
            }
        }
    }

    private func yt6AndCastFinish(
        videoId: String,
        key: String,
        sha: String?,
        result: Result<URL, Error>
    ) {
        guard cancellation?.isCancelled == false, activeVideoId == videoId else {
            return
        }
        switch result {
        case .failure(let error):
            fail(videoId: videoId, error: error)
        case .success(let temporary):
            let output = DownloadStore.videoFile(for: videoId)
            try? FileManager.default.removeItem(at: output)
            do {
                try FileManager.default.moveItem(at: temporary, to: output)
            } catch {
                fail(videoId: videoId, error: DownloadError.storage)
                return
            }
            YT6AndCast.log("save \(videoId): saved from andCast")
            AppLog.downloads("finished \(videoId) (andCast)")
            finishJob(reporting: .success(output))
            if let sha {
                let body = ["device": YT6AndCast.deviceId, "sha256": sha]
                YT6AndCast.call("v1/downloads/\(key)/delivered", body: body) { _ in }
            }
        }
    }
}
