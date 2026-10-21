import Foundation

/// Playlists in the local modes (REQUEST732): the catalog's playlists and
/// the owner's andCast lists (`/v1/state`: Watch Later, Favorites and his
/// own), kept on the iPod. «Downloaded only» shows only their saved
/// entries and hides a list with none; «andCast only» hides empty ones.
/// The guide's Watch Later is andCast's «watch-later», Liked its Favorites.
/// YouTube's own playlists are not kept on the iPod, so they are not here.
/// One list as a local mode shows it.
struct YT6ShownList {
    let id: String
    let title: String
    let videos: [Video]
}

extension YT6Library: PlaylistService {
    private var youtubeLists: InnertubeClient? {
        YT6Source.mode == .youtubeAndCast ? ServiceContainer.client : nil
    }

    /// Every list with the videos this mode can show, empty ones dropped.
    private var lists: [YT6ShownList] {
        let saved = YT6Source.mode == .downloadedOnly
        var byItem: [String: Video] = [:]
        if saved {
            for video in videos {
                if let item = YT6AndCastCatalog.shared.item(videoId: video.id) {
                    byItem[item.id] = video
                }
            }
        }
        let member: (String) -> Video? = { id in saved ? byItem[id] : self.video(item: id) }
        let own = YT6AndCastState.lists.map {
            YT6ShownList(id: $0.id, title: $0.title, videos: $0.items.compactMap(member))
        }
        let catalog = YT6AndCastCatalog.shared.playlists.map {
            YT6ShownList(id: $0.id, title: $0.title, videos: $0.items.compactMap(member))
        }
        return (own + catalog).filter { !$0.videos.isEmpty }
    }

    func fetchPlaylists(completion: @escaping (Result<[Playlist], Error>) -> Void) {
        if let youtubeLists {
            youtubeLists.fetchPlaylists(completion: completion)
            return
        }
        let shown = lists.map { list in
            Playlist(
                id: list.id,
                title: list.title,
                description: "",
                thumbnailURL: list.videos.first?.thumbnailURL,
                itemCount: list.videos.count
            )
        }
        YT6AndCast.log("library: \(shown.count) playlists (\(YT6Source.mode.title))")
        DispatchQueue.main.async { completion(.success(shown)) }
    }

    func fetchAddToPlaylistOptions(
        videoId: String,
        completion: @escaping (Result<[PlaylistAddOption], Error>) -> Void
    ) {
        if let youtubeLists {
            youtubeLists.fetchAddToPlaylistOptions(videoId: videoId, completion: completion)
            return
        }
        DispatchQueue.main.async { completion(.success([])) }
    }

    func fetchPlaylistVideos(
        playlistId: String,
        continuation: String?,
        completion: @escaping (Result<FeedPage, Error>) -> Void
    ) {
        if let youtubeLists {
            youtubeLists.fetchPlaylistVideos(
                playlistId: playlistId, continuation: continuation, completion: completion
            )
            return
        }
        let wanted = ["WL": "watch-later", "LL": "favorites"][playlistId] ?? playlistId
        let found = continuation == nil ? lists.first { $0.id == wanted }?.videos ?? [] : []
        DispatchQueue.main.async { completion(.success(FeedPage(videos: found))) }
    }
}

/// The owner's andCast lists from `/v1/state` (`lists`: Watch Later,
/// Favorites, his own), kept for the offline modes.
enum YT6AndCastState {
    struct List: Codable {
        let id: String
        let title: String
        let items: [String]
    }

    private static let key = "yt6.andcast.state"

    static var lists: [List] {
        let data = UserDefaults.standard.data(forKey: key)
        return data.flatMap { try? JSONDecoder().decode([List].self, from: $0) } ?? []
    }

    static func refresh() {
        guard YT6Source.mode != .downloadedOnly else {
            return
        }
        YT6AndCast.call("v1/state") { body in
            guard let raw = body?["lists"] as? [String: [String: Any]] else {
                return
            }
            let made = raw.map { key, value in
                List(
                    id: key,
                    title: value["Name"] as? String ?? (key == "watch-later" ? "Watch later" : key),
                    items: value["Items"] as? [String] ?? []
                )
            }
            UserDefaults.standard.set(try? JSONEncoder().encode(made), forKey: key)
            YT6AndCast.log("state: \(made.count) andCast lists")
        }
    }
}
