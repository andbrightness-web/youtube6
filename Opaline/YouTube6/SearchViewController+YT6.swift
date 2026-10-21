import UIKit

/// The youtube6 pieces of the results screen, kept on the controller.
final class YT6SearchResultsParts {
    let tabs = YT6SearchTabsView(titles: [
        YT6.string("search.videos", fallback: "VIDEOS"),
        YT6.string("search.playlists", fallback: "PLAYLISTS"),
        YT6.string("search.channels", fallback: "CHANNELS")
    ])
    let status = YT6SearchStatusView()
    let header = YT6SearchListHeader(
        frame: CGRect(x: 0, y: 0, width: 320, height: YT6SearchListHeader.height)
    )
    let playlists = YT6SearchKindList(kind: .playlists)
    let channels = YT6SearchKindList(kind: .channels)
}

/// `YTSearchResultsViewController_iPhone`: the 2.0.0 results screen. Opaline's
/// `SearchViewController` stays the engine of the VIDEOS tab (paging, refresh,
/// filters, the row menu); its own search bar, history panel and Filters
/// button give way to the 2.0.0 search bar over the title bar (`YT6Search`),
/// the query as the title (`loadView` @4c00c), the VIDEOS / PLAYLISTS /
/// CHANNELS tabs and the "Refine" button over the videos.
extension SearchViewController {
    private static var yt6Key: UInt8 = 0

    var yt6Parts: YT6SearchResultsParts {
        if let parts = objc_getAssociatedObject(self, &Self.yt6Key) as? YT6SearchResultsParts {
            return parts
        }
        let parts = YT6SearchResultsParts()
        objc_setAssociatedObject(self, &Self.yt6Key, parts, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return parts
    }

    /// End of `viewDidLoad`.
    func yt6SetUpResultsPage() {
        searchBar.removeFromSuperview()
        navigationItem.rightBarButtonItem = YT6Chrome.searchButton(for: self)
        // The other result types are the tabs, not a filter.
        filters.type = .video
        let parts = yt6Parts
        tableView.separatorStyle = .none
        parts.status.topMargin = YT6SearchListHeader.height
        tableView.backgroundView = parts.status
        tableView.tableHeaderView = parts.header
        parts.header.refineButton.addTarget(self, action: #selector(yt6Refine), for: .touchUpInside)
        yt6LayOutTabs()
        yt6WireKindLists()
        YT6PullRefresh.attach(under: view)
        YT6TapThrough.attach(under: view)
    }

    /// Called by `YT6Search` before the screen is pushed: one screen per
    /// query, all three tabs asked at once (`searchWithFilters:` @4b9a4).
    func yt6ShowResults(for query: String) {
        loadViewIfNeeded()
        title = query
        search(query: query)
        yt6Parts.playlists.load(query: query)
        yt6Parts.channels.load(query: query)
    }

    /// From `search(query:)`: a spinner while the first page loads.
    func yt6SearchDidStart() {
        if results.isEmpty {
            yt6Parts.status.showLoading()
        }
    }

    /// From `applySearchResult`: "No video results" for an empty answer; a
    /// failed one keeps upstream's alert.
    func yt6SearchDidFinish(_ result: Result<SearchPage, Error>) {
        let status = yt6Parts.status
        guard results.isEmpty, case .success = result else {
            status.hide()
            return
        }
        status.showEmpty(YT6.string("status.empty.video_results", fallback: "No video results"))
    }

    private func yt6LayOutTabs() {
        let parts = yt6Parts
        let tabs = parts.tabs
        let lists: [UIView] = [parts.playlists.table, parts.channels.table]
        for subview in [tabs, tabs.shadow] + lists {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        view.bringSubviewToFront(tabs.shadow)
        var constraints = [
            tabs.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabs.heightAnchor.constraint(equalToConstant: tabs.preferredHeight),
            tableView.topAnchor.constraint(equalTo: tabs.bottomAnchor),
            tabs.shadow.topAnchor.constraint(equalTo: tabs.bottomAnchor),
            tabs.shadow.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabs.shadow.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabs.shadow.heightAnchor.constraint(
                equalToConstant: tabs.shadow.image?.size.height ?? 2
            )
        ]
        constraints += lists.flatMap { yt6Constraints(pinning: $0, to: tableView) }
        NSLayoutConstraint.activate(constraints)
        tabs.onSelect = { [weak self] index in
            self?.yt6ShowTab(index)
        }
    }

    /// The other tabs lie exactly over the video list.
    private func yt6Constraints(pinning list: UIView, to other: UIView) -> [NSLayoutConstraint] {
        [
            list.topAnchor.constraint(equalTo: other.topAnchor),
            list.bottomAnchor.constraint(equalTo: other.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: other.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: other.trailingAnchor)
        ]
    }

    private func yt6WireKindLists() {
        let parts = yt6Parts
        parts.playlists.onOpenPlaylist = { [weak self] playlist in
            guard let self else {
                return
            }
            let screen = PlaylistVideosViewController(
                playlist: playlist,
                service: ServiceContainer.playlists,
                channelViewControllerFactory: self.channelViewControllerFactory,
                videoRouter: self.videoRouter
            )
            self.navigationController?.pushViewController(screen, animated: true)
        }
        parts.channels.onOpenChannel = { [weak self] channel in
            guard let self else {
                return
            }
            let screen = self.channelViewControllerFactory(channel.id, channel.title)
            self.navigationController?.pushViewController(screen, animated: true)
        }
    }

    private func yt6ShowTab(_ index: Int) {
        let parts = yt6Parts
        let tables = [tableView, parts.playlists.table, parts.channels.table]
        for (position, table) in tables.enumerated() {
            table.isHidden = position != index
            table.scrollsToTop = position == index
        }
    }

    /// "Refine" (`didPressRefineButton` @4b904): the filters screen; Done
    /// searches again from the first page.
    @objc
    private func yt6Refine() {
        let screen = YT6SearchFiltersViewController(filters: filters) { [weak self] chosen in
            guard let self, chosen != self.filters else {
                return
            }
            self.filters = chosen
            self.results = []
            self.tableView.reloadData()
            self.search(query: self.lastQuery)
        }
        let nav = UINavigationController(rootViewController: screen)
        YT6Chrome.styleNavigationBar(nav.navigationBar)
        present(nav, animated: true)
    }
}
