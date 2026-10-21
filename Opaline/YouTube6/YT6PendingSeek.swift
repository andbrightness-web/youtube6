import AVFoundation
import UIKit

/// Where the last seek is going, until the player has landed there. While a
/// seek waits for media (tv.sabr fetches the segment first), AVPlayer keeps
/// reporting the old time, and the bar jumped back to it and only moved to
/// the target once the segment had loaded (REQUEST721). The bar and the
/// time label show the target instead; subtitles, SponsorBlock and watch
/// time still get the real time.
final class YT6PendingSeek {
    var player: ObjectIdentifier?
    var seconds: Double?
}

extension VideoPlayerView {
    /// Upstream's seeks with `.zero` tolerances, remembering the target.
    func yt6Seek(_ player: AVPlayer, to time: CMTime) {
        let pending = yt6PendingSeek
        let target = CMTimeGetSeconds(time)
        if YT6.isEnabled {
            pending.player = ObjectIdentifier(player)
            pending.seconds = target
        }
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            DispatchQueue.main.async {
                // A newer seek owns the bar until it lands itself.
                if pending.seconds == target {
                    pending.seconds = nil
                }
            }
        }
    }

    /// The time the bar shows: the pending seek's target, if the current
    /// player is still on its way there.
    func yt6BarSeconds(_ seconds: Double) -> Double {
        let pending = yt6PendingSeek
        guard let target = pending.seconds,
              let player,
              pending.player == ObjectIdentifier(player)
        else {
            return seconds
        }
        return target
    }
}
