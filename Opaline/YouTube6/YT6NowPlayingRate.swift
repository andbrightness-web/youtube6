import AVFoundation
import MediaPlayer

/// Keeps the now-playing rate honest across play and pause (REQUEST721).
///
/// Opaline publishes `MPNowPlayingInfoPropertyPlaybackRate` only when a
/// session begins (the player is often still at rate 0 then) and on 5 s
/// position drifts, so a pause never reached the lock screen: the info
/// kept rate 1, and the iOS 6 lock screen of iPodOS (which reads that rate
/// as «playing») went on showing the video's title and artwork.
///
/// iOS 6.1.3 shows them only while the app plays: `-[SBAwayView
/// enableOrDisableNowPlayingPlugin]` @618c8 enables the
/// NowPlayingArtLockScreen plugin when `-isPlaying` @618f2, and
/// `-[SBMediaController isPlaying]` @b828c is the app's playing flag from
/// `MRMediaRemoteGetNowPlayingApplicationIsPlaying` @ba380. Apps that ran on
/// iOS 6 republished elapsed time with rate 0 on pause, rate back on play —
/// as aPod does (`-[APPlayer nowPlaying]`, accepted by the owner).
///
/// APPROXIMATION: YouTube 2.0.0 itself never set now-playing info (its
/// binary binds no `MPNowPlayingInfoCenter`); the lock screen player is
/// Opaline's, kept by the owner (REQUEST706).
final class YT6NowPlayingRate {
    static let shared = YT6NowPlayingRate()

    private var observation: NSKeyValueObservation?
    private var publishedRate: Float?

    /// Follows `player`'s rate; nil stops (the session ended).
    func track(_ player: AVPlayer?) {
        observation = nil
        publishedRate = nil
        guard let player else {
            return
        }
        observation = player.observe(\.rate, options: [.initial, .new]) { [weak self] player, _ in
            DispatchQueue.main.async {
                self?.publish(player)
            }
        }
    }

    private func publish(_ player: AVPlayer) {
        let rate = player.rate
        guard rate != publishedRate,
              var info = MPNowPlayingInfoCenter.default().nowPlayingInfo
        else {
            return
        }
        publishedRate = rate
        let elapsed = player.currentTime().seconds
        if elapsed.isFinite {
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        }
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        AppLog.player("now playing rate \(rate) at \(Int(elapsed.isFinite ? elapsed : 0)) s")
    }
}
