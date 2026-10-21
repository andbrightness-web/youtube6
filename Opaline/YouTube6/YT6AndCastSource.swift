import AVFoundation
import Foundation

/// Plays a video from andCast when the server has it and answers
/// (REQUEST722): the andCast iPod client's path (`preparePlayback:` in
/// `ACClient.m`) — `POST Items/{id}/PlaybackInfo` with its iOS 12 device
/// profile, direct play of an H.264/AAC MP4 when the file is one, otherwise
/// Jellyfin's HLS transcode. Anything else falls through to the YouTube
/// chain it wraps, so nothing changes for the videos the server lacks.
///
/// While the server plays there is no quality menu: the server picks the
/// stream for the iPod. Once YouTube plays, its menu is YouTube's.
final class YT6AndCastSource: VideoSource {
    /// Videos the server dropped mid-play: YouTube takes them for a while.
    private static var dropped: [String: Date] = [:]
    private static let dropCoolDown: TimeInterval = 5 * 60

    private let item: YT6AndCastCatalog.Item?
    private let network: VideoSource?
    private(set) var playingFromServer = false
    private var encodingSession: String?

    var name: String { playingFromServer ? "andcast" : (network?.name ?? "andcast") }
    var supportsQualitySelection: Bool {
        !playingFromServer && network?.supportsQualitySelection == true
    }
    var availableQualities: [VideoQuality] {
        playingFromServer ? [] : network?.availableQualities ?? []
    }
    var currentQuality: VideoQuality? { playingFromServer ? nil : network?.currentQuality }
    var currentCodecs: String? { playingFromServer ? "andCast" : network?.currentCodecs }
    var listsAudioTracks: Bool { network?.listsAudioTracks ?? false }
    var availableAudioTracks: [AudioTrack] { network?.availableAudioTracks ?? [] }
    var currentAudioTrack: AudioTrack? { network?.currentAudioTrack }

    init(item: YT6AndCastCatalog.Item?, network: VideoSource?) {
        self.item = item
        self.network = network
    }

    /// The source for this open, or nil to leave the YouTube chain alone.
    static func make(videoId: String, network: VideoSource) -> VideoSource? {
        let item = YT6AndCastCatalog.shared.item(videoId: videoId)
        switch YT6Source.mode {
        case .youtubeAndCast:
            guard let item, YT6AndCast.isSignedIn, !isDropped(videoId) else {
                return nil
            }
            YT6AndCast.log("play \(videoId): on the server as \(item.id), asking it first")
            return YT6AndCastSource(item: item, network: network)
        case .andCastOnly:
            return YT6AndCastSource(item: item, network: nil)
        case .downloadedOnly:
            return YT6AndCastSource(item: nil, network: nil)
        }
    }

    /// From `PlaybackFacade.recover`: the server stopped serving mid-play,
    /// so the rebuilt chain goes to YouTube and the shell seeks back to
    /// where the video was.
    static func noteRecovery(_ source: VideoSource?, videoId: String) {
        YT6PlaybackCache.forget(videoId: videoId)
        guard let own = source as? YT6AndCastSource, own.playingFromServer,
              YT6Source.mode == .youtubeAndCast else {
            return
        }
        dropped[videoId] = Date()
        YT6AndCastReach.noteFailure()
        YT6AndCast.log("play \(videoId): server stopped mid-play, YouTube takes over")
    }

    private static func isDropped(_ videoId: String) -> Bool {
        guard let at = dropped[videoId] else {
            return false
        }
        return Date().timeIntervalSince(at) < dropCoolDown
    }

    func loadPlayback(
        videoId: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let item else {
            let why = YT6Source.mode == .downloadedOnly
                ? "This video is not saved on this iPod."
                : "This video is not on your andCast server."
            fallBack(videoId, why: why, cancellation: cancellation, completion: completion)
            return
        }
        let started = Date()
        YT6AndCastReach.current { [weak self] base in
            guard let self, cancellation?.isCancelled != true else {
                return
            }
            guard let base else {
                let why = "andCast is not reachable."
                self.fallBack(videoId, why: why, cancellation: cancellation, completion: completion)
                return
            }
            YT6AndCastPlayback.resolve(item: item.id, base: base) { result in
                self.finish(
                    result,
                    videoId: videoId,
                    started: started,
                    cancellation: cancellation,
                    completion: completion
                )
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func finish(
        _ result: Result<YT6AndCastPlayback.Stream, Error>,
        videoId: String,
        started: Date,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard cancellation?.isCancelled != true else {
            return
        }
        switch result {
        case .success(let stream):
            let ms = Int(Date().timeIntervalSince(started) * 1_000)
            YT6AndCast.log("play \(videoId): from andCast, \(stream.method) in \(ms) ms")
            playingFromServer = true
            encodingSession = stream.isTranscode ? stream.session : nil
            let playerItem = AVPlayerItem(asset: AVURLAsset(url: stream.url))
            PlaybackBufferPolicy.configure(item: playerItem)
            completion(.success(PreparedPlayback(item: playerItem, duration: item?.seconds)))
        case .failure(let error):
            let why = "andCast: " + YT6AndCast.describe(Result<Void, Error>.failure(error))
            fallBack(videoId, why: why, cancellation: cancellation, completion: completion)
        }
    }

    private func fallBack(
        _ videoId: String,
        why: String,
        cancellation: CancellationToken?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        playingFromServer = false
        guard let network else {
            YT6AndCast.log("play \(videoId): \(why)")
            completion(.failure(YT6AndCastError.unavailable(why)))
            return
        }
        YT6AndCast.log("play \(videoId): \(why) — YouTube plays it")
        network.loadPlayback(videoId: videoId, cancellation: cancellation, completion: completion)
    }

    func selectQuality(
        _ quality: VideoQuality,
        resumeAt: Double?,
        completion: @escaping (Result<PreparedPlayback, Error>) -> Void
    ) {
        guard let network else {
            completion(.failure(YT6AndCastError.unavailable("No other quality on andCast.")))
            return
        }
        if playingFromServer {
            YT6AndCast.log("quality \(quality.label) picked: leaving andCast for YouTube")
            stopEncoding()
        }
        playingFromServer = false
        network.selectQuality(quality, resumeAt: resumeAt, completion: completion)
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

    func releaseResources() {
        stopEncoding()
        network?.releaseResources()
    }

    /// `stopEncoding:` — ends a Jellyfin transcode nobody watches.
    private func stopEncoding() {
        guard let session = encodingSession else {
            return
        }
        encodingSession = nil
        YT6AndCastPlayback.stopEncoding(session)
    }
}
