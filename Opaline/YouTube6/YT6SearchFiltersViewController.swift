import UIKit

/// `YTSearchFiltersViewController` ("Refine"): presented modally in its own
/// title bar (`-[YTNavigation_iPhone showSearchFilters:…]` @20fb4), "Search
/// Options" (`filters.title` @4ab60), Cancel on the left, Done on the right
/// (`loadView` @4a244/4a2e6). Sections of checkmark rows, the chosen one
/// ticked (`settingsSectionControllerWithTitle:…` @4afb0): SORT BY, UPLOAD
/// DATE, DURATION (@4a4e2–4a818). Done applies them as a new search
/// (`didPressDoneButton:` @4b1fc → `searchWithFilters:`), Cancel drops them.
///
/// Only the 2.0.0 options are offered; Opaline's last hour / this year /
/// medium length are not, and its result type is the screen's tabs. The
/// FEATURES section (closed captions only) is left out: Opaline has no such
/// filter. APPROXIMATION: the rows are a grouped iOS table in 2.0.0 fonts and
/// the bar buttons plain titles, not the 2.0.0 settings cells and plates.
final class YT6SearchFiltersViewController: UITableViewController {
    private struct Section {
        let titleKey: String
        let fallback: String
        let rows: [(key: String, fallback: String)]
    }

    private static let sections = [
        Section(titleKey: "filters.sort_by", fallback: "SORT BY", rows: [
            ("filters.sort_by.relevance", "Relevance"),
            ("filters.sort_by.upload_date", "Upload Date"),
            ("filters.sort_by.view_count", "View Count"),
            ("filters.sort_by.rating", "Rating")
        ]),
        Section(titleKey: "filters.upload_date", fallback: "UPLOAD DATE", rows: [
            ("filters.upload_date.anytime", "Anytime"),
            ("filters.upload_date.today", "Today"),
            ("filters.upload_date.this_week", "This Week"),
            ("filters.upload_date.this_month", "This Month")
        ]),
        Section(titleKey: "filters.duration", fallback: "DURATION", rows: [
            ("filters.duration.all", "All"),
            ("filters.duration.short", "Short (<4 minutes)"),
            ("filters.duration.long", "Long (>20 minutes)")
        ])
    ]
    private static let sorts: [SearchFilters.Sort] = [.relevance, .uploadDate, .viewCount, .rating]
    private static let dates: [SearchFilters.UploadDate] = [.any, .today, .thisWeek, .thisMonth]
    private static let durations: [SearchFilters.Duration] = [.any, .short, .long]

    private var filters: SearchFilters
    private let onDone: (SearchFilters) -> Void

    init(filters: SearchFilters, onDone: @escaping (SearchFilters) -> Void) {
        self.filters = filters
        self.onDone = onDone
        super.init(style: .grouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = YT6.string("filters.title", fallback: "Search Options")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: YT6.string("nav_bar.cancel", fallback: "Cancel"),
            style: .plain,
            target: self,
            action: #selector(cancel)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: YT6.string("nav_bar.done", fallback: "Done"),
            style: .done,
            target: self,
            action: #selector(done)
        )
        tableView.backgroundView = nil
        tableView.backgroundColor = YT6VideoRow.background
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        Self.sections.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Self.sections[section].rows.count
    }

    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
    ) -> String? {
        let item = Self.sections[section]
        return YT6.string(item.titleKey, fallback: item.fallback)
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row")
            ?? UITableViewCell(style: .default, reuseIdentifier: "row")
        let row = Self.sections[indexPath.section].rows[indexPath.row]
        cell.textLabel?.text = YT6.string(row.key, fallback: row.fallback)
        cell.textLabel?.font = UIFont(name: "HelveticaNeue-Light", size: 15)
        cell.textLabel?.textColor = UIColor(white: 51 / 255, alpha: 1)
        cell.tintColor = YT6.titleBarText
        let isChosen = selectedRow(in: indexPath.section) == indexPath.row
        cell.accessoryType = isChosen ? .checkmark : .none
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let row = indexPath.row
        switch indexPath.section {
        case 0:
            filters.sort = Self.sorts[row]
        case 1:
            filters.uploadDate = Self.dates[row]
        default:
            filters.duration = Self.durations[row]
        }
        tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
    }

    private func selectedRow(in section: Int) -> Int? {
        switch section {
        case 0:
            return Self.sorts.firstIndex(of: filters.sort)
        case 1:
            return Self.dates.firstIndex(of: filters.uploadDate)
        default:
            return Self.durations.firstIndex(of: filters.duration)
        }
    }

    @objc
    private func cancel() {
        dismiss(animated: true)
    }

    @objc
    private func done() {
        onDone(filters)
        dismiss(animated: true)
    }
}
