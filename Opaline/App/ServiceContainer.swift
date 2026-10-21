import Foundation

enum ServiceContainer {
    /// The app-wide HTTP transport: the URLSession core wrapped in decorators
    /// (logging now; authorizing/retrying to follow). Every service should route
    /// through this rather than touching URLSession directly.
    static let transport: HTTPTransport = LoggingTransport(
        AuthorizingTransport(URLSessionTransport())
    )

    /// Undecorated transport for the high-volume media plane (images, avatars):
    /// no per-request logging spam and no auth (these requests are anonymous).
    ///
    /// Its own session, capped: a page of twenty thumbnails fired at once
    /// shares one narrow link and they all land together seconds later, so
    /// the whole grid stays grey and then fills in a single blink. A few at
    /// a time finish one after another and the grid fills as you read it —
    /// each image costs 20-40ms on its own. The cap also keeps thumbnails
    /// out of the API session's connection pool.
    ///
    /// ponytail: fixed cap; make it link-aware only if it misbehaves on wifi.
    static let mediaTransport: HTTPTransport = URLSessionTransport(
        session: URLSession(configuration: mediaSessionConfiguration)
    )

    private static var mediaSessionConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 3
        return config
    }

    // Single InnertubeClient instance shared across all service protocols.
    // Each property is typed to the narrowest protocol the caller needs — DIP in action.
    /// youtube6 reads it too: `YT6Library` hands calls back to it when a
    /// screen that kept the library outlives «andCast only».
    static let client = InnertubeClient(transport: transport)

    static var feed: FeedService { yt6Pick(client as FeedService) }
    static var history: HistoryService { yt6Pick(client as HistoryService) }
    static var search: SearchService { yt6Pick(client as SearchService) }
    static var playlists: PlaylistService { yt6Pick(client as PlaylistService) }
    static var channel: ChannelService { yt6Pick(client as ChannelService) }
    static var channelTabs: ChannelTabService { yt6Pick(client as ChannelTabService) }
    static var subscribedChannels: SubscribedChannelsService {
        yt6Pick(client as SubscribedChannelsService)
    }
    /// Wrapped so a downloaded video keeps its page when the network is
    /// gone; online it is the plain client.
    static var watch: WatchService {
        guard YT6.isEnabled, YT6Source.mode != .downloadedOnly else {
            return offlineWatch
        }
        return YT6Library.shared
    }

    static let offlineWatch = OfflineWatchService(wrapping: client)
    static var engagement: EngagementService { client }
    static var account: AccountService { client }
    static var shorts: ShortsService { client }

    /// Legacy accessor — prefer narrow protocols above for new code.
    static var video: VideoService { client }

    /// Public per-channel Atom feeds for the new-content dots —
    /// anonymous traffic, so it rides the undecorated media transport.
    static let channelRSS: ChannelRSSFeedService = ChannelRSSService(
        transport: mediaTransport
    )

    /// Content-language/region preferences for Innertube requests
    /// (localization plan Phase 2 points `InnertubeContexts` here).
    static let localePreferences: LocalePreferences = DefaultLocalePreferences()
}
