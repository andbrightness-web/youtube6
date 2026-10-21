import Foundation

/// The running side of an andCast save (see `YT6AndCastDownload`).
extension VideoDownloader {
    /// Counts the transfer into the shared progress: the option's size is
    /// an estimate, the server's ready copy has the real one.
    private final class Reported {
        var bytes: Int64 = 0
    }

    /// `fetchTracks` for an andCast option.
    func yt6FetchFromAndCast(videoId: String, option: DownloadOption) {
        let item = YT6AndCastDownload.item(of: option)
        let token = cancellation
        YT6AndCastJobs.setStage(.preparing(0), videoId: videoId)
        let waiting: () -> Bool = { [weak self] in self?.yt6Runs(videoId, token) == true }
        YT6AndCastJobs.prepare(
            item: item, quality: option.height, keepWaiting: waiting
        ) { [weak self] job in
            self?.yt6AndCastUpdate(videoId: videoId, option: option, job: job, token: token)
        }
    }

    private func yt6Runs(_ videoId: String, _ token: CancellationToken?) -> Bool {
        cancellation === token && token?.isCancelled == false && activeVideoId == videoId
    }

    private func yt6AndCastUpdate(
        videoId: String,
        option: DownloadOption,
        job: YT6AndCastJobs.Job?,
        token: CancellationToken?
    ) {
        guard yt6Runs(videoId, token) else {
            return
        }
        guard let job else {
            YT6AndCastJobs.setStage(nil, videoId: videoId)
            fail(videoId: videoId, error: YT6AndCastError.unavailable("andCast did not answer"))
            return
        }
        switch job.status {
        case "ready":
            YT6AndCastJobs.setStage(.ready, videoId: videoId)
            YT6AndCast.log("save \(videoId): copy ready on the server, \(job.bytes / 1_048_576) MB")
            yt6AndCastTransfer(videoId: videoId, option: option, job: job, token: token)
        case "queued", "preparing":
            let stage: YT6AndCastJobs.Stage = job.converting
                ? .converting(job.progress) : .preparing(job.progress)
            YT6AndCastJobs.setStage(stage, videoId: videoId)
        default:
            YT6AndCastJobs.setStage(nil, videoId: videoId)
            fail(videoId: videoId, error: YT6AndCastError.unavailable("andCast: \(job.status)"))
        }
    }

    private func yt6AndCastTransfer(
        videoId: String,
        option: DownloadOption,
        job: YT6AndCastJobs.Job,
        token: CancellationToken?
    ) {
        YT6AndCastReach.current { [weak self] base in
            guard let self, self.yt6Runs(videoId, token) else {
                return
            }
            let path = "v1/downloads/\(job.key)/file"
            guard let base, let request = YT6AndCast.api(path, base: base) else {
                YT6AndCastJobs.setStage(nil, videoId: videoId)
                self.fail(videoId: videoId, error: YT6AndCastError.unavailable("andCast went away"))
                return
            }
            let reported = Reported()
            YT6AndCastFileFetch.start(
                request,
                total: job.bytes,
                folder: DownloadStore.folder(for: videoId),
                token: token,
                progress: { [weak self] fraction in
                    YT6AndCastJobs.setStage(.downloading(fraction), videoId: videoId)
                    let target = Int64(fraction * Double(option.bytes))
                    self?.advance(by: target - reported.bytes)
                    reported.bytes = target
                },
                completion: { [weak self] result in
                    self?.yt6AndCastCheck(videoId: videoId, job: job, token: token, result: result)
                }
            )
        }
    }

    /// Size and sha256 against the server's before the copy counts.
    private func yt6AndCastCheck(
        videoId: String,
        job: YT6AndCastJobs.Job,
        token: CancellationToken?,
        result: Result<URL, Error>
    ) {
        guard yt6Runs(videoId, token) else {
            return
        }
        guard case .success(let joined) = result else {
            YT6AndCastJobs.setStage(nil, videoId: videoId)
            if case .failure(let error) = result {
                YT6AndCast.log("save \(videoId): transfer stopped, parts kept for the next try")
                fail(videoId: videoId, error: error)
            }
            return
        }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let values = try? joined.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(values?.fileSize ?? 0)
            let sha = YT6AndCastFileFetch.sha256(of: joined)
            DispatchQueue.main.async {
                let check = (size: size, sha: sha)
                self?.yt6AndCastFinish(videoId: videoId, job: job, joined: joined, check: check)
            }
        }
    }

    private func yt6AndCastFinish(
        videoId: String,
        job: YT6AndCastJobs.Job,
        joined: URL,
        check: (size: Int64, sha: String?)
    ) {
        YT6AndCastJobs.setStage(nil, videoId: videoId)
        let folder = DownloadStore.folder(for: videoId)
        let sizeOK = job.bytes <= 0 || check.size == job.bytes
        let shaOK = job.sha256 == nil || job.sha256 == check.sha
        guard sizeOK, shaOK else {
            let sizes = "\(check.size)/\(job.bytes)"
            YT6AndCast.log("save \(videoId): check failed (size \(sizes)), fetching again")
            YT6AndCastFileFetch.dropParts(in: folder)
            try? FileManager.default.removeItem(at: joined)
            fail(videoId: videoId, error: DownloadError.missingFile)
            return
        }
        let output = DownloadStore.videoFile(for: videoId)
        try? FileManager.default.removeItem(at: output)
        guard (try? FileManager.default.moveItem(at: joined, to: output)) != nil else {
            fail(videoId: videoId, error: DownloadError.storage)
            return
        }
        YT6AndCastFileFetch.dropParts(in: folder)
        YT6AndCast.log("save \(videoId): saved from andCast, size and sha256 match")
        AppLog.downloads("finished \(videoId) (andCast)")
        finishJob(reporting: .success(output))
        if let sha = check.sha {
            let body = ["device": YT6AndCast.deviceId, "sha256": job.sha256 ?? sha]
            YT6AndCast.call("v1/downloads/\(job.key)/delivered", body: body) { _ in }
        }
        YT6AndCastJobs.forget(item: job.item, quality: job.quality)
    }
}
