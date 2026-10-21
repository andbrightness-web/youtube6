import AVFoundation
import Foundation

/// The andCast quality menu and the YouTube-side forwards of
/// `YT6AndCastSource`.
extension YT6AndCastSource {
    /// `andcast-0` is the original/copy; `andcast-<height>` a tier.
    static func quality(_ tier: Int?, source: Int?, copy: Bool) -> VideoQuality {
        guard let tier, !copy else {
            let label = source.map { "\($0)p · andCast" } ?? "Original · andCast"
            return VideoQuality(id: "andcast-0", label: label, height: source, fps: nil)
        }
        let label = "\(tier)p · andCast"
        return VideoQuality(id: "andcast-\(tier)", label: label, height: tier, fps: nil)
    }

    /// A pick from the andCast menu: the same video again at that tier.
    func serverQuality(
        _ item: YT6AndCastItem,
        tier: Int?,
        label: String,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        YT6AndCastReach.current { [weak self] base in
            guard let self, let base else {
                completion(.failure(YT6AndCastError.unavailable("andCast is not reachable.")))
                return
            }
            YT6AndCast.log("quality \(label) picked on andCast")
            self.stopEncoding()
            YT6AndCastPlayback.resolve(item: item.id, base: base, tier: tier) { result in
                switch result {
                case .success(let stream):
                    self.playingFromServer = true
                    self.stream = stream
                    self.encodingSession = stream.isTranscode ? stream.session : nil
                    let playerItem = AVPlayerItem(asset: stream.asset)
                    PlaybackBufferPolicy.configure(item: playerItem)
                    completion(.success(PreparedPlayback(item: playerItem, duration: item.seconds)))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }

    func selectAudioTrack(
        _ track: AudioTrack,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let network else {
            completion(.failure(YT6AndCastError.unavailable("No other audio on andCast.")))
            return
        }
        stopEncoding()
        playingFromServer = false
        network.selectAudioTrack(track, resumeAt: resumeAt, completion: completion)
    }

    func probeQualities(videoId: String, completion: @escaping ([VideoQuality]) -> Void) {
        guard let network else {
            completion([])
            return
        }
        network.probeQualities(videoId: videoId, completion: completion)
    }

    func probeAudioTracks(videoId: String, completion: @escaping ([AudioTrack]) -> Void) {
        guard let network else {
            completion([])
            return
        }
        network.probeAudioTracks(videoId: videoId, completion: completion)
    }
}
