import Foundation

/// The watch page in «andCast only»: title, channel and date from the
/// catalog, the description from `/v1/items/{id}` (`Overview`), up next
/// from `/v1/recommendations/next` (the andCast player's own), else the
/// channel's newest. andCast has no likes or comments: those stay empty,
/// and nothing here reaches YouTube.
extension YT6Library: WatchService {
    private static func page(_ video: Video, overview: String?, related: [Video]) -> WatchPage {
        let info = ChannelInfo(
            id: video.channelId ?? "",
            title: video.channelName,
            avatarURL: video.channelAvatarURL,
            subscriberCountText: nil,
            bannerURL: nil,
            isVerified: false,
            description: nil,
            contactInfo: nil,
            videoCountText: nil
        )
        return WatchPage(
            video: video,
            description: overview,
            channelInfo: info,
            subscribeButtonText: nil,
            isSubscribed: false,
            relatedVideos: related,
            likeCount: nil,
            likeStatus: nil,
            commentCount: nil,
            nextVideo: related.first,
            playlistTitle: nil,
            playlistVideos: nil
        )
    }

    func fetchWatchPage(
        video: Video,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    ) {
        guard let item = YT6AndCastCatalog.shared.item(videoId: video.id) else {
            DispatchQueue.main.async {
                completion(.failure(YT6AndCastError.unavailable("This video is not on andCast.")))
            }
            return
        }
        let shown = YT6LibraryVideo.make(item)
        let group = DispatchGroup()
        var overview: String?
        var next: [Video] = []
        group.enter()
        YT6AndCast.call("v1/items/\(item.id)") { body in
            overview = body?["Overview"] as? String
            group.leave()
        }
        group.enter()
        upNext(item.id) { found in
            next = found
            group.leave()
        }
        group.notify(queue: .main) { [weak self] in
            let channel = self?.videos(ofChannel: shown.channelId ?? "") ?? []
            let related = next.isEmpty ? channel.filter { $0.id != shown.id } : next
            YT6AndCast.log("library: watch page \(video.id), \(related.count) up next")
            let page = Self.page(shown, overview: overview, related: Array(related.prefix(20)))
            completion(.success(page))
        }
    }

    /// `/v1/recommendations/next?id=` — entries by andCast id.
    private func upNext(_ item: String, completion: @escaping ([Video]) -> Void) {
        let tz = TimeZone.current.secondsFromGMT() / 60
        let query = ["id": item, "tz": "\(tz)"]
        YT6AndCast.call("v1/recommendations/next", query: query) { [weak self] body in
            let entries = body?["items"] as? [Any] ?? []
            completion(entries.compactMap { entry in
                let id = (entry as? [String: Any])?["id"] as? String ?? entry as? String
                return id.flatMap { self?.video(item: $0) }
            })
        }
    }

    // MARK: Nothing from YouTube

    // swiftlint:disable:next function_parameter_count
    func fetchDirectPlayback(
        videoId: String,
        client: PlaybackClient,
        poToken: String?,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<DirectPlaybackInfo, Error>) -> Void
    ) {
        completion(.failure(YT6AndCastError.unavailable("andCast only")))
    }

    func fetchComments(
        videoId: String,
        continuation: String?,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<CommentsPage, Error>) -> Void
    ) {
        let empty = CommentsPage(title: nil, comments: [], continuation: nil, sortOptions: [])
        DispatchQueue.main.async { completion(.success(empty)) }
    }

    func fetchQueuePage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        completion(.success(FeedPage(videos: [])))
    }

    func fetchShuffledQueue(
        video: Video,
        params: String,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    ) {
        completion(.failure(YT6AndCastError.unavailable("andCast only")))
    }

    func fetchWatchtimeURLs(videoId: String, completion: @escaping (WatchtimeURLs?) -> Void) {
        completion(nil)
    }

    func fetchCaptionTracks(videoId: String, completion: @escaping ([SubtitleTrack]) -> Void) {
        completion([])
    }

    func fetchAudioTrackList(videoId: String, completion: @escaping ([AudioTrackInfo]) -> Void) {
        completion([])
    }
}
