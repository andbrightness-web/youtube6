import UIKit

/// The PLAYLISTS and CHANNELS tabs of the results screen. In 2.0.0 each is
/// its own feed view with its own request, without the video filters
/// (`-[YTSearchResultsViewController searchWithFilters:]` @4bb12/4bb68):
/// `YTTableFeedView` of `YTPlaylistCell_iPhone` / `YTChannelResultCell_iPhone`
/// with "No playlist results" / "No channel results" when empty
/// (`initWithVideosView:` @71440–71508). Here: the same Innertube `/search`
/// the video tab uses, with the type set as Opaline's filters encode it.
/// APPROXIMATION: the first page only.
final class YT6SearchKindList: NSObject {
    enum Kind {
        case playlists
        case channels
    }

    let kind: Kind
    let table = UITableView(frame: .zero, style: .plain)
    var onOpenPlaylist: ((Playlist) -> Void)?
    var onOpenChannel: ((YT6SearchChannel) -> Void)?
    private let status = YT6SearchStatusView()
    private var playlists: [Playlist] = []
    private var channels: [YT6SearchChannel] = []
    private var token = CancellationToken()

    private var emptyMessage: String {
        switch kind {
        case .playlists:
            return YT6.string("status.empty.playlist_results", fallback: "No playlist results")
        case .channels:
            return YT6.string("status.empty.channel_results", fallback: "No channel results")
        }
    }

    init(kind: Kind) {
        self.kind = kind
        super.init()
        table.dataSource = self
        table.delegate = self
        table.separatorStyle = .none
        table.backgroundColor = YT6VideoRow.background
        table.backgroundView = status
        table.rowHeight = kind == .playlists ? YT6PlaylistCell.height : YT6SearchChannelCell.height
        table.register(
            YT6SearchChannelCell.self, forCellReuseIdentifier: YT6SearchChannelCell.reuseId
        )
        table.isHidden = true
    }

    func load(query: String) {
        guard let client = ServiceContainer.search as? InnertubeClient else {
            return
        }
        token.cancel()
        let token = CancellationToken()
        self.token = token
        playlists = []
        channels = []
        table.reloadData()
        status.showLoading()
        let type: SearchFilters.ContentType = kind == .playlists ? .playlist : .channel
        client.yt6SearchItems(
            query: query, type: type, cancellationToken: token
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.token === token else {
                    return
                }
                self.apply(result)
            }
        }
    }

    private func apply(_ result: Result<[[String: Any]], Error>) {
        switch result {
        case .success(let items):
            playlists = items.compactMap { InnertubeClient.yt6SearchPlaylist(from: $0) }
            channels = items.compactMap { InnertubeClient.yt6SearchChannel(from: $0) }
            table.reloadData()
            let isEmpty = kind == .playlists ? playlists.isEmpty : channels.isEmpty
            if isEmpty {
                status.showEmpty(emptyMessage)
            } else {
                status.hide()
            }
        case .failure(let error):
            // `expandAndShowErrorMessage:` — the error in place of the list.
            status.showEmpty(error.localizedDescription)
        }
    }
}

extension YT6SearchKindList: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        kind == .playlists ? playlists.count : channels.count
    }

    func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        if kind == .playlists {
            return YT6PlaylistCell.dequeue(
                from: tableView, at: indexPath, with: playlists[indexPath.row]
            )
        }
        let cell = tableView.dequeueReusableCell(
            withIdentifier: YT6SearchChannelCell.reuseId, for: indexPath
        )
        (cell as? YT6SearchChannelCell)?.configure(with: channels[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        switch kind {
        case .playlists:
            onOpenPlaylist?(playlists[indexPath.row])
        case .channels:
            onOpenChannel?(channels[indexPath.row])
        }
    }
}

extension InnertubeClient {
    private static func yt6SearchItems(in data: Data) -> [[String: Any]] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        let sections = json.digArray(
            "contents",
            "twoColumnSearchResultsRenderer",
            "primaryContents",
            "sectionListRenderer",
            "contents"
        ) ?? []
        return sections.flatMap { $0.digArray("itemSectionRenderer", "contents") ?? [] }
    }

    /// `/search` with only a result type set (the playlist and channel tabs);
    /// hands back the items of the first page.
    func yt6SearchItems(
        query: String,
        type: SearchFilters.ContentType,
        cancellationToken: CancellationToken,
        completion: @escaping (Result<[[String: Any]], Error>) -> Void
    ) {
        var filters = SearchFilters()
        filters.type = type
        var body = webContext
        body["query"] = query
        body["params"] = filters.encodedParams
        guard let url = URL(string: "\(baseURL)/search"),
              let data = try? JSONSerialization.data(withJSONObject: body)
        else {
            completion(.failure(APIError.invalidURL))
            return
        }
        let headers = [HTTPHeader.contentType: HTTPHeaderValue.contentTypeJSON]
        api.post(
            url: url, body: data, headers: headers, cancellationToken: cancellationToken
        ) { result in
            completion(result.map { Self.yt6SearchItems(in: $0) })
        }
    }
}
