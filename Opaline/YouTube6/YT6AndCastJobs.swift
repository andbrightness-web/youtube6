import Foundation

/// The server's prepared copies for this iPod (REQUEST729, 731), as the
/// andCast client keeps them (`ACDownloads.m`): one job per video and
/// quality, `POST /v1/downloads` {item, mode, quality, device}, `GET
/// /v1/downloads/{key}` until `ready`. The server keeps a ready copy until
/// it is told `delivered` (with its sha256) or `release`d, so the key is
/// kept on the iPod: a later save or play of the same video picks the same
/// job up — ready at once, or still preparing — and never starts another.
/// `release` only when the owner cancels; errors, timeouts, a killed app or
/// a mode switch keep the copy.
enum YT6AndCastJobs {
    struct Job: Codable {
        let key: String
        let item: String
        let quality: Int
        var status: String
        var bytes: Int64
        var sha256: String?
        var progress: Double
        var converting: Bool
    }

    /// Where a copy stands, for the row's grey line and the bar
    /// (`statusFor:` in `ACLibraryViewController.m`).
    enum Stage {
        case preparing(Double)
        case converting(Double)
        case ready
        case downloading(Double)

        var text: String {
            switch self {
            case .preparing(let done):
                return done > 0 ? "Preparing on server \(Int(done * 100))%" : "Preparing on server…"
            case .converting(let done):
                return Stage.preparing(done).text + " · Converting for iPod"
            case .ready:
                return "Ready on server · arriving"
            case .downloading(let done):
                return "Downloading \(Int(done * 100))%"
            }
        }
    }

    private static let key = "yt6.andcast.jobs"
    private static let pollEvery: TimeInterval = 3
    /// Per video while it is being saved; read by `YT6DownloadBar`.
    private(set) static var stages: [String: Stage] = [:]

    private static var jobs: [String: Job] {
        get {
            let data = UserDefaults.standard.data(forKey: key)
            return data.flatMap { try? JSONDecoder().decode([String: Job].self, from: $0) } ?? [:]
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    static func job(item: String, quality: Int) -> Job? {
        jobs[item + "-\(quality)"]
    }

    /// Any job of this item, the highest quality first.
    static func anyJob(item: String) -> Job? {
        jobs.values.filter { $0.item == item }.max { $0.quality < $1.quality }
    }

    static func setStage(_ stage: Stage?, videoId: String) {
        stages[videoId] = stage
        NotificationCenter.default.post(name: VideoDownloader.didProgressNotification, object: nil)
    }

    /// Asks for (or picks up) the copy, then reports every answer until it
    /// is ready or failed. `keepWaiting` stops the polls when false.
    static func prepare(
        item: String,
        quality: Int,
        keepWaiting: @escaping () -> Bool,
        update: @escaping (Job?) -> Void
    ) {
        if let known = job(item: item, quality: quality) {
            let key = known.key.prefix(8)
            YT6AndCast.log("job \(item): picking up the server's copy \(key) (\(known.status))")
            poll(known.key, item: item, quality: quality, keepWaiting: keepWaiting, update: update)
            return
        }
        let body: [String: Any] = [
            "item": item, "mode": "video", "quality": quality, "device": YT6AndCast.deviceId
        ]
        YT6AndCast.call("v1/downloads", body: body) { reply in
            let made = reply.flatMap { record($0, item: item, quality: quality) }
            update(made)
            if let made, made.status != "ready", keepWaiting() {
                after(pollEvery) {
                    poll(
                        made.key,
                        item: item,
                        quality: quality,
                        keepWaiting: keepWaiting,
                        update: update
                    )
                }
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    private static func poll(
        _ key: String,
        item: String,
        quality: Int,
        keepWaiting: @escaping () -> Bool,
        update: @escaping (Job?) -> Void
    ) {
        YT6AndCast.callStatus("v1/downloads/\(key)") { status, reply in
            guard let reply else {
                // Only a server that says the job is gone loses it; an
                // unreachable one keeps it for the next try.
                if status == 404 {
                    forget(item: item, quality: quality)
                }
                update(nil)
                return
            }
            let job = record(reply, item: item, quality: quality)
            update(job)
            guard let job, ["queued", "preparing"].contains(job.status), keepWaiting() else {
                return
            }
            after(pollEvery) {
                poll(key, item: item, quality: quality, keepWaiting: keepWaiting, update: update)
            }
        }
    }

    /// The server's answer, kept under its item and quality.
    private static func record(_ reply: [String: Any], item: String, quality: Int) -> Job? {
        guard let key = reply["key"] as? String, let status = reply["status"] as? String else {
            return nil
        }
        let job = Job(
            key: key,
            item: item,
            quality: quality,
            status: status,
            bytes: Int64(reply["bytes"] as? Int ?? 0),
            sha256: reply["sha256"] as? String,
            progress: reply["preparationProgress"] as? Double ?? 0,
            converting: reply["method"] as? String == "Converted"
        )
        var all = jobs
        if ["failed", "blocked", "unavailable"].contains(status) {
            all[item + "-\(quality)"] = nil
        } else {
            all[item + "-\(quality)"] = job
        }
        jobs = all
        return job
    }

    static func forget(item: String, quality: Int) {
        var all = jobs
        all[item + "-\(quality)"] = nil
        jobs = all
    }

    /// The owner does not want this copy any more (cancel, delete before
    /// it arrived): `POST /v1/downloads/{key}/release`.
    static func release(item: String) {
        let mine = jobs.values.filter { $0.item == item }
        for job in mine {
            forget(item: item, quality: job.quality)
            let body: [String: Any] = ["device": YT6AndCast.deviceId, "smart": false]
            YT6AndCast.call("v1/downloads/\(job.key)/release", body: body) { reply in
                let how = reply == nil ? "not reached" : "done"
                YT6AndCast.log("job \(item): released on the server (\(how))")
            }
        }
    }

    private static func after(_ seconds: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
