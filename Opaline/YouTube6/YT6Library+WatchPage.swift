import Foundation

/// The watch page of a video the server has, in «YouTube + andCast» and
/// «andCast only» (REQUEST727, 734): YouTube's page when YouTube answers in
/// time — likes, views, description, channel, comments — with any field it
/// leaves empty filled from the andCast base; without YouTube (unreachable,
/// bot check, error, timeout) the andCast base itself: title, channel and
/// date from the catalog, the description from `/v1/items/{id}`
/// (`Overview`), views and subscribers from the stats base, the channel's
/// avatar, up next from the server. In «andCast only» every list on the
/// page is kept to the server's videos. Likes and chapters are not in what
/// the andCast API hands out.
extension YT6Library {
    private static let maxRelated = 20

    private static func page(
        _ page: WatchPage,
        video: Video,
        description: String?,
        channel: ChannelInfo
    ) -> WatchPage {
        WatchPage(
            video: video,
            description: description,
            channelInfo: channel,
            subscribeButtonText: page.subscribeButtonText,
            isSubscribed: page.isSubscribed,
            relatedVideos: page.relatedVideos,
            likeCount: page.likeCount,
            likeStatus: page.likeStatus,
            commentCount: page.commentCount,
            nextVideo: page.nextVideo,
            playlistTitle: page.playlistTitle,
            playlistVideos: page.playlistVideos
        )
    }

    private static func withViews(_ video: Video, _ views: String?) -> Video {
        var copy = Video(
            id: video.id,
            title: video.title,
            channelId: video.channelId,
            channelName: video.channelName,
            channelAvatarURL: video.channelAvatarURL,
            thumbnailURL: video.thumbnailURL,
            viewCount: views,
            publishedAt: video.publishedAt,
            duration: video.duration,
            isLive: video.isLive,
            playlistId: video.playlistId,
            isShort: video.isShort
        )
        copy.feedbackActions = video.feedbackActions
        return copy
    }

    func fetchWatchPage(
        video: Video,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    ) {
        let youtube = ServiceContainer.offlineWatch
        let mode = YT6Source.mode
        guard mode != .downloadedOnly, YT6AndCast.isSignedIn,
              let item = YT6AndCastCatalog.shared.item(videoId: video.id) else {
            notOnServer(video, cancellationToken: cancellationToken, completion: completion)
            return
        }
        let decide: (WatchPage?) -> Void = { [weak self] page in
            guard let page else {
                self?.andCastPage(item, completion: completion)
                return
            }
            if mode == .andCastOnly {
                self?.serverOnly(page, item: item, completion: completion)
            } else {
                self?.filled(page, item: item, completion: completion)
            }
        }
        // «YouTube + andCast» waits longer: there YouTube is the usual case.
        let wait: TimeInterval = mode == .andCastOnly ? 6 : 10
        YT6Race.first(within: wait, fallback: nil, completion: decide) { done in
            youtube.fetchWatchPage(video: video, cancellationToken: nil) { result in
                done(try? result.get())
            }
        }
    }

    private func notOnServer(
        _ video: Video,
        cancellationToken: CancellationToken?,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    ) {
        guard YT6Source.mode == .andCastOnly else {
            ServiceContainer.offlineWatch.fetchWatchPage(
                video: video, cancellationToken: cancellationToken, completion: completion
            )
            return
        }
        DispatchQueue.main.async {
            completion(.failure(YT6AndCastError.unavailable("This video is not on andCast.")))
        }
    }

    /// YouTube's page with every list kept to the server's videos.
    private func serverOnly(
        _ page: WatchPage,
        item: YT6AndCastItem,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    ) {
        YT6AndCastChannelMap.learn(videoId: page.video.id, youtubeChannel: page.channelInfo?.id)
        let onServer = { (video: Video) in YT6AndCastCatalog.shared.item(videoId: video.id) != nil }
        upNext(item.id) { next in
            var seen = Set<String>([page.video.id])
            let mixed = page.relatedVideos.filter(onServer) + next
            let related = mixed.filter { seen.insert($0.id).inserted }
            let kept = Array(related.prefix(Self.maxRelated))
            let id = page.video.id
            let count = kept.count
            YT6AndCast.log("library: watch page \(id) from YouTube, \(count) up next on andCast")
            var shown = WatchPage(
                video: page.video,
                description: page.description,
                channelInfo: page.channelInfo,
                subscribeButtonText: page.subscribeButtonText,
                isSubscribed: page.isSubscribed,
                relatedVideos: kept,
                likeCount: page.likeCount,
                likeStatus: page.likeStatus,
                commentCount: page.commentCount,
                nextVideo: kept.first,
                playlistTitle: page.playlistTitle,
                playlistVideos: page.playlistVideos?.filter(onServer)
            )
            shown.shuffleParams = nil
            completion(.success(shown))
        }
    }

    /// YouTube's page with what it left empty taken from the andCast base.
    private func filled(
        _ page: WatchPage,
        item: YT6AndCastItem,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    ) {
        YT6AndCastChannelMap.learn(videoId: page.video.id, youtubeChannel: page.channelInfo?.id)
        let base = YT6LibraryVideo.make(item)
        var video = page.video
        if video.viewCount?.isEmpty != false {
            video = Self.withViews(video, base.viewCount)
        }
        let local = localInfo(base.channelId ?? "")
        let channel = page.channelInfo.map { YT6Library.merge($0, local: local) } ?? local
        let needsText = page.description?.isEmpty != false
        let finish: (String?) -> Void = { overview in
            YT6AndCast.log("library: watch page \(video.id) from YouTube, gaps from andCast")
            let text = needsText ? overview : page.description
            completion(.success(Self.page(page, video: video, description: text, channel: channel)))
        }
        guard needsText else {
            finish(nil)
            return
        }
        YT6AndCast.call("v1/items/\(item.id)") { body in
            finish(body?["Overview"] as? String)
        }
    }

    private func andCastPage(
        _ item: YT6AndCastItem,
        completion: @escaping (Result<WatchPage, Error>) -> Void
    ) {
        let shown = YT6LibraryVideo.make(item)
        let info = localInfo(shown.channelId ?? "")
        details(item.id) { [weak self] overview, next in
            let channel = self?.videos(ofChannel: shown.channelId ?? "") ?? []
            let related = next.isEmpty ? channel.filter { $0.id != shown.id } : next
            let kept = Array(related.prefix(Self.maxRelated))
            let count = kept.count
            YT6AndCast.log("library: watch page \(shown.id) from andCast, \(count) up next")
            completion(.success(WatchPage(
                video: shown,
                description: overview,
                channelInfo: info,
                subscribeButtonText: nil,
                isSubscribed: false,
                relatedVideos: kept,
                likeCount: nil,
                likeStatus: nil,
                commentCount: nil,
                nextVideo: kept.first,
                playlistTitle: nil,
                playlistVideos: nil
            )))
        }
    }
}
