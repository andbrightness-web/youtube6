import Foundation
import QuartzCore

/// Warms the video that plays next while this one plays (step 3 of
/// research/YOUTUBE6-SPEED-2026-10-21.md): its `/player`, solved `n` and init
/// segments land in `YT6PlaybackCache`, so autoplay, the queue's next entry
/// or a tap on the first suggestion starts with only media left to fetch.
///
/// Only the step that would play first is warmed, and only one video per
/// start: each warm is one more `/player`, and how many of those YouTube
/// tolerates before a bot check is not known. A byte-range step warms its
/// `/player` alone — its proxy cancels whatever it does not serve, which is
/// the playing video's segments.
enum YT6Preload {
    /// After the first frame plays. APPROXIMATION: late enough that the
    /// playing video's opening segments are in, early enough for a short
    /// video's end.
    static let delay: TimeInterval = 10

    private static var warmed: Set<String> = []
    /// The source doing the warming, held until it is done.
    private static var running: VideoSource?

    static func warm(_ videoId: String, apiClient: WatchService) {
        let steps = YT6ChainMemory.ordered(PlaybackChainSettings.activeSteps(), logs: false)
        guard running == nil, !warmed.contains(videoId),
              !DownloadStore.isDownloaded(videoId),
              let step = steps.first,
              let source = step.make(apiClient) as? InnertubeVideoSource else {
            return
        }
        warmed.insert(videoId)
        running = source
        let started = CACurrentMediaTime()
        AppLog.player("[Speed] preload \(videoId) on \(step.id)")
        let done: (Bool) -> Void = { ok in
            DispatchQueue.main.async {
                let ms = Int((CACurrentMediaTime() - started) * 1_000)
                AppLog.player("[Speed] preload \(videoId) \(ok ? "ready" : "failed") +\(ms) ms")
                running?.releaseResources()
                running = nil
            }
        }
        guard source.deliveryFactory.label == "sabr" else {
            source.fetchInfo(videoId: videoId, cancellation: nil) { done((try? $0.get()) != nil) }
            return
        }
        source.loadPlayback(videoId: videoId, cancellation: nil) { done((try? $0.get()) != nil) }
    }
}

extension WatchViewController {
    /// Once this video plays, warm what comes after it: the queue's next
    /// entry, or the suggestion autoplay would pick.
    func yt6PreloadWhenPlaying() {
        let token = pageLoadToken
        YT6Speed.shared.onStarted = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + YT6Preload.delay) {
                self?.yt6PreloadNext(token)
            }
        }
    }

    private func yt6PreloadNext(_ token: CancellationToken) {
        guard !token.isCancelled else {
            return
        }
        let suggestion = AutoplayPreference.isEnabled ? watchPage?.nextVideo : nil
        guard let next = queue.nextVideo ?? suggestion else {
            return
        }
        YT6Preload.warm(next.id, apiClient: client)
    }
}
