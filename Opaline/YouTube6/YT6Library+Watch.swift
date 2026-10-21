import Foundation

/// The watch service in «andCast only»; the page itself is in
/// `YT6Library+WatchPage.swift`. Comments and tracking come from YouTube
/// when it answers.
extension YT6Library: WatchService {
    /// The service the other modes use, for whoever kept this object.
    var other: WatchService? {
        YT6Source.mode == .andCastOnly ? nil : ServiceContainer.offlineWatch
    }

    /// The description and up next, asked together.
    func details(_ item: String, completion: @escaping (String?, [Video]) -> Void) {
        let group = DispatchGroup()
        var overview: String?
        var next: [Video] = []
        group.enter()
        YT6AndCast.call("v1/items/\(item)") { body in
            overview = body?["Overview"] as? String
            group.leave()
        }
        group.enter()
        upNext(item) { found in
            next = found
            group.leave()
        }
        group.notify(queue: .main) {
            completion(overview, next)
        }
    }

    /// `/v1/recommendations/next?id=` — entries by andCast id.
    func upNext(_ item: String, completion: @escaping ([Video]) -> Void) {
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
        if let other {
            other.fetchDirectPlayback(
                videoId: videoId,
                client: client,
                poToken: poToken,
                cancellationToken: cancellationToken,
                completion: completion
            )
            return
        }
        completion(.failure(YT6AndCastError.unavailable("andCast only")))
    }

    func fetchComments(
        videoId: String,
        continuation: String?,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<CommentsPage, Error>) -> Void
    ) {
        if let other {
            other.fetchComments(
                videoId: videoId,
                continuation: continuation,
                cancellationToken: cancellationToken,
                completion: completion
            )
            return
        }
        // YouTube's comments first; the andCast base keeps none, so the
        // fallback is an empty list.
        let empty = CommentsPage(title: nil, comments: [], continuation: nil, sortOptions: [])
        let fallback = Result<CommentsPage, Error>.success(empty)
        YT6Race.first(within: 6, fallback: fallback, completion: completion) { done in
            ServiceContainer.offlineWatch.fetchComments(
                videoId: videoId,
                continuation: continuation,
                cancellationToken: cancellationToken
            ) { result in
                done((try? result.get()).map { .success($0) })
            }
        }
    }

    func fetchQueuePage(
        continuation: String,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        if let other {
            other.fetchQueuePage(continuation: continuation, completion: completion)
            return
        }
        completion(.success(FeedPage(videos: [])))
    }

    func fetchShuffledQueue(
        video: Video,
        params: String,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    ) {
        if let other {
            other.fetchShuffledQueue(video: video, params: params, completion: completion)
            return
        }
        completion(.failure(YT6AndCastError.unavailable("andCast only")))
    }

    /// YouTube's tracking URLs even here: the media comes from andCast,
    /// the watch still goes to the account's history.
    func fetchWatchtimeURLs(videoId: String, completion: @escaping (WatchtimeURLs?) -> Void) {
        if let other {
            other.fetchWatchtimeURLs(videoId: videoId, completion: completion)
            return
        }
        ServiceContainer.offlineWatch.fetchWatchtimeURLs(videoId: videoId) { urls in
            YT6AndCastStats.shared.youtubeAnswered(videoId: videoId, reached: urls != nil)
            completion(urls)
        }
    }

    func fetchCaptionTracks(videoId: String, completion: @escaping ([SubtitleTrack]) -> Void) {
        if let other {
            other.fetchCaptionTracks(videoId: videoId, completion: completion)
            return
        }
        completion([])
    }

    func fetchAudioTrackList(videoId: String, completion: @escaping ([AudioTrackInfo]) -> Void) {
        if let other {
            other.fetchAudioTrackList(videoId: videoId, completion: completion)
            return
        }
        completion([])
    }
}
