import UIKit

/// `YTSearchController` + the search side of `YTNavigation_iPhone`: one
/// search bar for the whole app (`initWithServices:` @203dc), brought over
/// the current screen by the title bar's search button
/// (`showSearchForQuery:fromView:` @20e84, query nil — the last query stays
/// in the field). Submitting pushes a results screen titled with the query
/// (`performSearch:` @14a28 → `showSearchResultsForQuery:fromView:`).
final class YT6Search: NSObject {
    static let shared = YT6Search()

    private let searchView = YT6SearchView()
    private let history = SearchHistoryStore.shared
    private let service: SearchService = ServiceContainer.search
    private weak var host: UINavigationController?
    /// The suggest service's last answer (`_suggestions`).
    private var serverSuggestions: [String] = []
    private var suggestToken = CancellationToken()

    override private init() {
        super.init()
        searchView.delegate = self
        searchView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    private static func root(of viewController: UIViewController) -> UIViewController {
        var root = viewController
        while let parent = root.parent {
            root = parent
        }
        return root
    }

    /// The title bar's search button (`didPressSearchButton:` @2ce64).
    func show(from viewController: UIViewController) {
        guard let nav = viewController.navigationController else {
            return
        }
        host = nav
        let top = nav.isNavigationBarHidden
            ? nav.view.safeAreaInsets.top
            : nav.navigationBar.frame.minY
        let area = CGRect(
            x: 0, y: top, width: nav.view.bounds.width, height: nav.view.bounds.height - top
        )
        // APPROXIMATION of the z-order: 2.0.0's search view is over the
        // content view, the watch page included. The watch page here sits
        // over the navigation in the root container, so the search view
        // goes there, above it.
        let container: UIView = Self.root(of: nav).view
        searchView.frame = nav.view.convert(area, to: container)
        container.addSubview(searchView)
        container.bringSubviewToFront(searchView)
        searchView.gainFocus()
        // `searchViewDidGainFocus` @146b8 refreshes the list.
        updateSuggestions()
    }

    /// `updateSuggestions` @14aec: history first — all of it for an empty
    /// query, else the entries starting with it — then the suggest service's
    /// answers not listed yet.
    private func updateSuggestions() {
        let query = searchView.query
        var items = history.queries.filter { query.isEmpty || $0.hasPrefix(query) }
        for suggestion in serverSuggestions where !items.contains(suggestion) {
            items.append(suggestion)
        }
        searchView.setSuggestions(items)
    }

    private func fetchSuggestions(for query: String) {
        suggestToken.cancel()
        let token = CancellationToken()
        suggestToken = token
        service.fetchSearchSuggestions(
            query: query, cancellationToken: token
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self,
                      self.suggestToken === token,
                      case .success(let items) = result
                else {
                    return
                }
                self.serverSuggestions = items
                self.updateSuggestions()
            }
        }
    }

    private func pushResults(for query: String) {
        guard let nav = host,
              let results = ToolbarManager.shared.searchViewControllerFactory?()
        else {
            return
        }
        results.yt6ShowResults(for: query)
        // `-[YTNavigation_iPhone pushViewController:fromView:]` @22b74/22ca4
        // starts with `collapseWatchIfExpanded`: an expanded video goes to
        // the collapsed player, still playing (REQUEST720).
        Self.root(of: nav).children
            .compactMap { $0 as? PlayerPanelViewController }
            .first { $0.isExpanded }?
            .collapse(animated: true)
        nav.pushViewController(results, animated: true)
    }
}

extension YT6Search: YT6SearchViewDelegate {
    /// `queryDidChange:` @14724: an empty field drops the suggestions and
    /// shows the history; anything else asks the suggest service.
    func searchViewQueryDidChange(_ query: String) {
        guard !query.isEmpty else {
            suggestToken.cancel()
            serverSuggestions = []
            updateSuggestions()
            return
        }
        fetchSuggestions(for: query)
    }

    /// `performSearch:` @14a28.
    func searchViewDidSubmit(_ query: String) {
        searchView.field.text = query
        searchView.loseFocus()
        history.add(query)
        pushResults(for: query)
    }

    /// `searchSuggestionAddDidPress:` @149a4: "suggestion " into the field,
    /// still focused; the list is left as it is.
    func searchViewDidAppend(_ suggestion: String) {
        searchView.field.text = suggestion + " "
    }

    func searchViewCanDelete(_ suggestion: String) -> Bool {
        history.queries.contains(suggestion)
    }

    func searchViewDelete(_ suggestion: String) {
        history.remove(suggestion)
        updateSuggestions()
    }
}

extension UIViewController {
    /// Target of the 2.0.0 search button in the title bar.
    @objc
    func yt6OpenSearch() {
        YT6Search.shared.show(from: self)
    }
}
