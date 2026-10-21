import Foundation

/// The feed, history, search, channel and guide services of the local
/// modes. Answers arrive on the main queue.
extension YT6Library: FeedService, HistoryService, SearchService, SubscribedChannelsService {
    typealias PageReply = (Result<FeedPage, Error>) -> Void

    /// Something that kept this object (background refresh, the
    /// downloader) asks while the app is back on YouTube.
    private var youtube: InnertubeClient? {
        YT6Source.mode == .youtubeAndCast ? ServiceContainer.client : nil
    }

    private func answer<T>(_ value: T, _ completion: @escaping (Result<T, Error>) -> Void) {
        DispatchQueue.main.async { completion(.success(value)) }
    }

    func fetchHomeFeed(completion: @escaping PageReply) {
        if let youtube {
            youtube.fetchHomeFeed(completion: completion)
            return
        }
        loadShelf { [weak self] in
            guard let self else {
                return
            }
            let page = self.firstPage("home")
            YT6AndCast.log("library: What To Watch, \(page.videos.count) videos")
            completion(.success(page))
        }
    }

    func fetchCategoryFeed(browseId: String, completion: @escaping PageReply) {
        if let youtube {
            youtube.fetchCategoryFeed(browseId: browseId, completion: completion)
            return
        }
        answer(FeedPage(videos: []), completion)
    }

    func fetchSubscriptionFeed(completion: @escaping PageReply) {
        if let youtube {
            youtube.fetchSubscriptionFeed(completion: completion)
            return
        }
        answer(firstPage("all"), completion)
    }

    func fetchNextPage(continuation: String, completion: @escaping PageReply) {
        if let youtube {
            youtube.fetchNextPage(continuation: continuation, completion: completion)
            return
        }
        answer(nextPage(continuation), completion)
    }

    func fetchSubscriptionsNextPage(continuation: String, completion: @escaping PageReply) {
        if let youtube {
            youtube.fetchSubscriptionsNextPage(
                continuation: continuation, completion: completion
            )
            return
        }
        answer(nextPage(continuation), completion)
    }

    /// `/v1/history` (latest position per video) in «andCast only»; the
    /// saved videos offline.
    func fetchHistory(completion: @escaping PageReply) {
        if let youtube {
            youtube.fetchHistory(completion: completion)
            return
        }
        guard YT6Source.mode == .andCastOnly else {
            answer(FeedPage(videos: videos), completion)
            return
        }
        YT6AndCast.call("v1/history", query: ["limit": "200"]) { [weak self] body in
            let entries = body?["items"] as? [[String: Any]] ?? []
            let ids = entries.compactMap { $0["id"] as? String }
            let list = ids.compactMap { self?.video(item: $0) }
            completion(.success(FeedPage(videos: list)))
        }
    }

    func fetchHistoryNextPage(
        continuation: String,
        token: String,
        completion: @escaping PageReply
    ) {
        if let youtube {
            youtube.fetchHistoryNextPage(
                continuation: continuation, token: token, completion: completion
            )
            return
        }
        answer(FeedPage(videos: []), completion)
    }

    // swiftlint:disable:next function_parameter_count
    func search(
        query: String,
        filters: SearchFilters?,
        continuation: String?,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<SearchPage, Error>) -> Void
    ) {
        let page = continuation.map(nextPage) ?? firstPage("search", argument: query)
        if continuation == nil {
            YT6AndCast.log("library: search on the iPod, \(search(query).count) found")
        }
        answer(SearchPage(videos: page.videos, continuation: page.continuation), completion)
    }

    func fetchSearchSuggestions(
        query: String,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        answer(Array(search(query).prefix(8).map(\.title)), completion)
    }

    func fetchSubscribedChannels(
        completion: @escaping (Result<[SubscribedChannel], Error>) -> Void
    ) {
        answer(channels, completion)
    }
}

extension YT6Library: ChannelService, ChannelTabService {
    private func info(_ channelId: String) -> ChannelInfo {
        let list = videos(ofChannel: channelId)
        let channel = YT6AndCastCatalog.shared.channel(channelId)
        let avatar = channel.flatMap { YT6AndCast.artworkURL($0.id, revision: $0.artwork) }
        return ChannelInfo(
            id: channelId,
            title: channel?.title ?? list.first?.channelName ?? "",
            avatarURL: avatar ?? list.first?.channelAvatarURL,
            subscriberCountText: nil,
            bannerURL: nil,
            isVerified: false,
            description: nil,
            contactInfo: nil,
            videoCountText: "\(list.count) videos"
        )
    }

    private func reply<T>(_ value: T, _ completion: @escaping (Result<T, Error>) -> Void) {
        DispatchQueue.main.async { completion(.success(value)) }
    }

    func fetchChannelInfo(
        channelId: String,
        completion: @escaping (Result<ChannelInfo, Error>) -> Void
    ) {
        reply(info(channelId), completion)
    }

    func fetchChannelPage(
        channelId: String,
        completion: @escaping (Result<ChannelPage, Error>) -> Void
    ) {
        let page = ChannelPage(
            info: info(channelId),
            videosPage: firstPage("channel", argument: channelId),
            subscribeButtonText: nil,
            isSubscribed: false
        )
        reply(page, completion)
    }

    func enrichChannelInfo(
        channelId: String,
        tvInfo: ChannelInfo,
        onEnriched: @escaping (ChannelInfo) -> Void
    ) {}

    func fetchChannelTab(
        channelId: String,
        params: String,
        completion: @escaping (Result<ChannelTabPage, Error>) -> Void
    ) {
        let videos = firstPage("channel", argument: channelId)
        reply(ChannelTabPage(feedPage: videos, filterChips: []), completion)
    }

    func fetchChannelTabNextPage(continuation: String, completion: @escaping PageReply) {
        reply(nextPage(continuation), completion)
    }

    func fetchChannelPlaylists(
        channelId: String,
        params: String,
        completion: @escaping (Result<PlaylistsPage, Error>) -> Void
    ) {
        reply(PlaylistsPage(playlists: [], continuation: nil), completion)
    }

    func fetchChannelPlaylistsNextPage(
        continuation: String,
        completion: @escaping (Result<PlaylistsPage, Error>) -> Void
    ) {
        reply(PlaylistsPage(playlists: [], continuation: nil), completion)
    }

    func fetchChannelSearch(
        channelId: String,
        query: String,
        completion: @escaping PageReply
    ) {
        let found = Set(search(query).map(\.id))
        let list = videos(ofChannel: channelId).filter { found.contains($0.id) }
        reply(FeedPage(videos: list), completion)
    }

    func fetchChannelSearchNextPage(continuation: String, completion: @escaping PageReply) {
        reply(FeedPage(videos: []), completion)
    }
}
