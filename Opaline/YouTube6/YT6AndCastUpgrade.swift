import AVFoundation
import UIKit

/// A video the server has to convert (REQUEST731): it plays at once from
/// Jellyfin's live HLS transcode, and the same prepared copy «Save to iPod»
/// would ask for is started for this iPod. When it is ready the player
/// moves onto it at the same position (only while it plays, so a paused
/// video does not start by itself), the transcode is stopped, and later
/// opens play the copy directly. The copy stays on the server: a watched
/// video is not stored on the iPod and is never marked `delivered`
/// (REQUEST732: «просмотр это просто кэш»).
enum YT6AndCastUpgrade {
    private static let retryEvery: TimeInterval = 5
    private static let maxTries = 120

    static func watch(item: String, videoId: String, source: YT6AndCastSource) {
        guard !item.isEmpty else {
            return
        }
        let quality = YT6AndCastDownload.preferredQuality
        YT6AndCast.log("play \(videoId): asking the server for a \(quality)p iPod copy meanwhile")
        PlaybackProgress.report?("andCast is converting for the iPod…")
        let waiting: () -> Bool = { [weak source] in
            source.map { stillPlays(videoId, $0) } ?? false
        }
        YT6AndCastJobs.prepare(
            item: item, quality: quality, keepWaiting: waiting
        ) { [weak source] job in
            guard let source, let job, job.status == "ready" else {
                return
            }
            YT6AndCast.log("play \(videoId): the iPod copy is ready on the server")
            trySwitch(videoId: videoId, job: job, source: source, tries: 0)
        }
    }

    private static func stillPlays(_ videoId: String, _ source: YT6AndCastSource) -> Bool {
        guard let facade = YT6AndCastStats.shared.currentFacade else {
            return false
        }
        return facade.currentVideoId == videoId && facade.activeVideoSource === source
    }

    private static func trySwitch(
        videoId: String,
        job: YT6AndCastJobs.Job,
        source: YT6AndCastSource,
        tries: Int
    ) {
        guard stillPlays(videoId, source), tries < maxTries,
              let watch = YT6AndCastStats.shared.currentFacade?.context as? WatchViewController,
              let player = watch.videoPlayerView?.player,
              let base = YT6AndCastReach.base, let token = YT6AndCast.session?.token else {
            return
        }
        guard player.rate > 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + retryEvery) {
                trySwitch(videoId: videoId, job: job, source: source, tries: tries + 1)
            }
            return
        }
        let stream = YT6AndCastPlayback.copy(job, base: base, token: token)
        let position = player.currentTime()
        let item = AVPlayerItem(asset: stream.asset)
        PlaybackBufferPolicy.configure(item: item)
        source.switchedToCopy(stream)
        let second = Int(CMTimeGetSeconds(position))
        YT6AndCast.log("play \(videoId): moving onto the prepared copy at \(second) s")
        watch.attachPrepared(PreparedPlayback(item: item), resumeAt: position)
    }
}
