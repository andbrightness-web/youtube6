import UIKit

/// One row of a 2.0.0 settings table: `YTSettingsSectionRow`
/// (`rowWithTitle:detailTextBlock:selectBlock:` @14f94,
/// `checkmarkRowWithTitle:selectBlock:` @15044) plus the two other row types
/// the settings screen shows — the account card and the card button.
struct YT6SettingsRow {
    enum Kind {
        /// `YTSettingsCell`: title left, value (or checkmark) right.
        case value
        /// `YTCardButtonCell`: one centered-left line in link blue.
        case button
        /// `YTUserAccountCell`: avatar and account name.
        case account
    }

    var kind = Kind.value
    let title: String
    var detail: String?
    var checked = false
    /// youtube6: the SponsorBlock seek-bar color of a category row.
    var swatch: UIColor?
    /// Overrides the kind's text color ("SIGN OUT" is dark, not blue).
    var textColor: UIColor?
    var image: UIImage?
    var select: (() -> Void)?

    init(title: String, detail: String? = nil, select: (() -> Void)? = nil) {
        self.title = title
        self.detail = detail
        self.select = select
    }
}

/// A `YTSettingsSectionController` (`initWithTitle:rows:` @151dc): an
/// uppercase title row and its cards. `note` has no 2.0.0 analog.
struct YT6SettingsSection {
    let title: String?
    let rows: [YT6SettingsRow]
    var note: String?

    init(title: String?, rows: [YT6SettingsRow], note: String? = nil) {
        self.title = title
        self.rows = rows
        self.note = note
    }
}

/// Colors and metrics shared by the settings screens.
enum YT6SettingsStyle {
    /// `+[UIColor backgroundColor]` @3f5532 — the table behind the cards.
    static let background = UIColor(white: 237 / 255, alpha: 1)
    /// `+[YTColor XDarkTextColor]` @3f5408 — section titles, account name.
    static let xDarkText = UIColor(white: 51 / 255, alpha: 1)
    /// `+[YTColor darkTextColor]` @3f5438 — row titles and values.
    static let darkText = UIColor(white: 102 / 255, alpha: 1)
    /// `+[YTColor mediumTextColor]` @3f5468.
    static let mediumText = UIColor(white: 153 / 255, alpha: 1)
    /// `+[UIColor moreButtonTextColor]` @3f598c — card buttons.
    static let buttonText = UIColor(red: 27 / 255, green: 127 / 255, blue: 204 / 255, alpha: 1)
    /// `+[YTItemListHeader headerHeight]` @3f1658.
    static let headerHeight: CGFloat = 36
    /// `+[YTSettingsCell preferredHeight]` @3dd400.
    static let rowHeight: CGFloat = 44
    /// `+[YTCardButtonCell preferredHeight]` @3cbab4.
    static let buttonHeight: CGFloat = 51
    /// `+[YTUserAccountCell preferredHeight]` @78c90.
    static let accountHeight: CGFloat = 55

    static func header(_ key: String) -> String {
        key.localized.uppercased(with: Locale(identifier: AppLanguage.effective.rawValue))
    }

    /// youtube6 rows Opaline has no string for, in the interface language.
    static func text(russian: String, english: String) -> String {
        YT6.isRussianInterface ? russian : english
    }

    /// `+[YTSettingsViewController stringWithBOOL:]` @4db5c.
    static func yesNo(_ value: Bool) -> String {
        value
            ? YT6.string("settings.yes", fallback: "Yes")
            : YT6.string("settings.no", fallback: "No")
    }
}

/// The 2.0.0 settings table (`YTSettingsViewController` +
/// `YTSectionedTableViewController`): a plain table on the 237 gray, no
/// separators, each section an uppercase title row and grouped cards, the
/// `bar_shadow` under the title bar (`YTTopShadowView` @4cd94).
final class YT6SettingsViewController: UIViewController {
    private struct PlacedRow {
        let row: YT6SettingsRow
        let position: YT6SettingsCell.Position
    }

    private enum Entry {
        case header(String)
        case row(PlacedRow)
        case note(String)
    }

    private let provider: (YT6SettingsViewController) -> [YT6SettingsSection]
    private let table = UITableView(frame: .zero, style: .plain)
    private let shadow = UIImageView(image: YT6.stretchableImage("bar_shadow"))
    private var entries: [Entry] = []
    private var workers: [SettingsViewController.Page: SettingsViewController] = [:]

    init(
        title: String,
        provider: @escaping (YT6SettingsViewController) -> [YT6SettingsSection]
    ) {
        self.provider = provider
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func makeEntries(_ section: YT6SettingsSection) -> [Entry] {
        guard !section.rows.isEmpty else {
            return []
        }
        var list: [Entry] = section.title.map { [.header($0)] } ?? []
        let count = section.rows.count
        for (index, row) in section.rows.enumerated() {
            let position = YT6SettingsCell.Position(row: index, of: count)
            list.append(.row(PlacedRow(row: row, position: position)))
        }
        if let note = section.note {
            list.append(.note(note))
        }
        return list
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = YT6SettingsStyle.background
        table.backgroundColor = YT6SettingsStyle.background
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.frame = view.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(table)
        shadow.isUserInteractionEnabled = false
        view.addSubview(shadow)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reload()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let height = shadow.image?.size.height ?? 0
        shadow.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: height)
    }

    /// Rebuilds every row from the current settings.
    func reload() {
        entries = provider(self).flatMap(Self.makeEntries)
        table.reloadData()
    }

    /// The hidden Opaline settings page whose rows, values and handlers a
    /// 2.0.0 row stands for. A child, so its pushes land on this stack and
    /// what it presents goes through `presentOnTop`.
    func worker(_ page: SettingsViewController.Page) -> SettingsViewController {
        if let worker = workers[page] {
            return worker
        }
        let worker = SettingsViewController(page: page)
        addChild(worker)
        worker.didMove(toParent: self)
        workers[page] = worker
        return worker
    }

    /// 2.0.0 rows for these Opaline rows of `page`, in that order; rows the
    /// page hides right now (a switched-off option's details) are skipped.
    func opaline(
        _ page: SettingsViewController.Page,
        _ rows: [SettingsViewController.Row]
    ) -> [YT6SettingsRow] {
        let source = worker(page)
        return rows.compactMap { source.yt6Row($0) }
    }

    /// Presents above whatever this screen already shows (a picker, say).
    func presentOnTop(_ controller: UIViewController, completion: (() -> Void)? = nil) {
        var top: UIViewController = navigationController ?? self
        while let presented = top.presentedViewController {
            top = presented
        }
        top.present(controller, animated: true, completion: completion)
    }
}

// MARK: - Table

extension YT6SettingsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        entries.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch entries[indexPath.row] {
        case let .header(title):
            return YT6SettingsTextCell(text: title, isHeader: true)
        case let .note(text):
            return YT6SettingsTextCell(text: text, isHeader: false)
        case let .row(placed):
            let cell = YT6SettingsCell(style: .default, reuseIdentifier: nil)
            cell.configure(placed.row, position: placed.position)
            return cell
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch entries[indexPath.row] {
        case .header:
            return YT6SettingsStyle.headerHeight
        case let .note(text):
            return YT6SettingsTextCell.noteHeight(text, width: tableView.bounds.width)
        case let .row(placed):
            return YT6SettingsCell.height(of: placed.row.kind)
        }
    }

    func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        guard case let .row(placed) = entries[indexPath.row] else {
            return false
        }
        return placed.row.select != nil
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard case let .row(placed) = entries[indexPath.row] else {
            return
        }
        placed.row.select?()
    }
}

extension UIViewController {
    /// The guide's Settings row: `-[YTNavigation_iPhone
    /// showSettingsFromRect:inView:]` @221fc pushes the settings screen onto
    /// the current stack (`pushViewController:fromView:` @2225e).
    func yt6OpenSettings() {
        guard let nav = navigationController,
              !(nav.topViewController is YT6SettingsViewController)
        else {
            return
        }
        nav.pushViewController(YT6SettingsRoot.make(), animated: true)
    }
}
