import AVFoundation
import QuartzCore

/// Speed marks in `opaline.log` (REQUEST695, step 0 of
/// research/YOUTUBE6-SPEED-2026-10-21.md): tap → first frame and → playing,
/// seek → playing again, and every stall with its reason, so each speed
/// change is measured in milliseconds before and after.
final class YT6Speed {
    static let shared = YT6Speed()

    private var tapAt: CFTimeInterval?
    private var frameAt: CFTimeInterval?
    private var seekAt: CFTimeInterval?
    private var stallAt: CFTimeInterval?
    private var observations: [NSKeyValueObservation] = []
    private var jumpObserver: NSObjectProtocol?

    private static func ms(since start: CFTimeInterval) -> Int {
        Int((CACurrentMediaTime() - start) * 1_000)
    }

    /// A video was asked for (the watch page starts its playback).
    func markTap(_ videoId: String) {
        onMain {
            self.tapAt = CACurrentMediaTime()
            self.frameAt = self.tapAt
            self.seekAt = nil
            self.stallAt = nil
            AppLog.hls("[Speed] tap \(videoId)")
        }
    }

    /// Follows the player that now shows the video.
    func watch(player: AVPlayer, layer: AVPlayerLayer) {
        observations = [
            layer.observe(\.isReadyForDisplay, options: [.new]) { [weak self] layer, _ in
                guard layer.isReadyForDisplay else {
                    return
                }
                self?.onMain {
                    self?.frameReady()
                }
            },
            player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                let status = player.timeControlStatus
                let reason = player.reasonForWaitingToPlay?.rawValue ?? "-"
                self?.onMain {
                    self?.statusChanged(status, reason: reason)
                }
            }
        ]
        if let jumpObserver {
            NotificationCenter.default.removeObserver(jumpObserver)
        }
        jumpObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemTimeJumped,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            // The first jump is the resume position of a fresh video.
            if self?.tapAt == nil {
                self?.seekAt = CACurrentMediaTime()
            }
        }
    }

    private func frameReady() {
        guard let frameAt else {
            return
        }
        self.frameAt = nil
        AppLog.hls("[Speed] first frame +\(Self.ms(since: frameAt)) ms")
    }

    private func statusChanged(_ status: AVPlayer.TimeControlStatus, reason: String) {
        let now = CACurrentMediaTime()
        switch status {
        case .playing:
            if let tapAt {
                AppLog.hls("[Speed] playing +\(Self.ms(since: tapAt)) ms after tap")
            } else if let seekAt {
                AppLog.hls("[Speed] seek → playing +\(Self.ms(since: seekAt)) ms")
            } else if let stallAt {
                AppLog.hls("[Speed] stall over +\(Self.ms(since: stallAt)) ms")
            }
            tapAt = nil
            seekAt = nil
            stallAt = nil
        case .waitingToPlayAtSpecifiedRate:
            if tapAt == nil, seekAt == nil, stallAt == nil {
                stallAt = now
                AppLog.hls("[Speed] stall (\(reason))")
            }
        default:
            break
        }
    }

    private func onMain(_ work: @escaping () -> Void) {
        Thread.isMainThread ? work() : DispatchQueue.main.async(execute: work)
    }

}
