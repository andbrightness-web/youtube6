import UIKit

/// The guide table (`YTGuideTableView` + `YTBaseGuideCell`/`YTGuideCell_iPhone`
/// + `YTGuideSectionHeader`).
///
/// Sections, in 2.0.0 order: ACCOUNT (Sign In / the account, with Watch
/// Later, History, Playlists and Liked disclosed under it), What To Watch and
/// My Subscriptions, FROM YOUTUBE (Live), Settings.
final class YT6GuideViewController: UITableViewController {
    enum Row: Equatable {
        case account
        case section(YT6Section)
        case settings
    }

    var onSelect: ((Row) -> Void)?
    private(set) var selectedSection: YT6Section = .whatToWatch
    /// `-[YTGuideTableView toggleDiscloseAccount]`.
    private var accountDisclosed = true

    private var sections: [(header: String?, rows: [Row])] {
        let signedIn = OAuthClient.shared.isSignedIn
        var account: [Row] = [.account]
        if signedIn, accountDisclosed {
            account += YT6Section.allCases.filter(\.needsAccount).map(Row.section)
        }
        return [
            (YT6.string("guide_section.account", fallback: "ACCOUNT"), account),
            (nil, [.section(.whatToWatch), .section(.subscriptions)]),
            (YT6.string("guide_section.from_youtube", fallback: "FROM YOUTUBE"), [.section(.live)]),
            (nil, [.settings])
        ]
    }

    init() {
        super.init(style: .plain)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundColor = YT6.guideBackground
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.rowHeight = YT6.guideRowHeight
        tableView.register(YT6GuideCell.self, forCellReuseIdentifier: YT6GuideCell.reuseID)
        tableView.contentInsetAdjustmentBehavior = .always
        for name in [UserProfileStore.didUpdateNotification, .userDidSignOut] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(reload),
                name: name,
                object: nil
            )
        }
    }

    @objc
    func reload() {
        tableView.reloadData()
    }

    func select(_ section: YT6Section) {
        selectedSection = section
        tableView.reloadData()
    }

    private func row(at indexPath: IndexPath) -> Row {
        sections[indexPath.section].rows[indexPath.row]
    }

    // MARK: Table

    override func numberOfSections(in tableView: UITableView) -> Int {
        sections.count
    }

    override func tableView(
        _ tableView: UITableView,
        numberOfRowsInSection section: Int
    ) -> Int {
        sections[section].rows.count
    }

    override func tableView(
        _ tableView: UITableView,
        heightForHeaderInSection section: Int
    ) -> CGFloat {
        sections[section].header == nil ? 0 : YT6.guideHeaderHeight
    }

    override func tableView(
        _ tableView: UITableView,
        viewForHeaderInSection section: Int
    ) -> UIView? {
        sections[section].header.map(YT6GuideSectionHeader.init)
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: YT6GuideCell.reuseID,
            for: indexPath
        )
        guard let guideCell = cell as? YT6GuideCell else {
            return cell
        }
        switch row(at: indexPath) {
        case .account:
            configureAccount(guideCell)
        case .section(let section):
            guideCell.configure(
                YT6GuideCell.Content(
                    title: section.title,
                    icon: section.icon,
                    selected: section == selectedSection
                )
            )
        case .settings:
            guideCell.configure(
                YT6GuideCell.Content(
                    title: YT6.string("guide.settings", fallback: "Settings"),
                    icon: "settings_guide"
                )
            )
        }
        return guideCell
    }

    private func configureAccount(_ cell: YT6GuideCell) {
        let signedIn = OAuthClient.shared.isSignedIn
        let loggedIn = UserProfileStore.shared.displayName
            ?? YT6.string("guide.account_loggedin.access", fallback: "Your account")
        cell.configure(
            YT6GuideCell.Content(
                title: signedIn ? loggedIn : YT6.string("guide.account", fallback: "Sign In"),
                disclosure: signedIn ? (accountDisclosed ? "collapse_guide" : "expand_guide") : nil
            )
        )
        cell.onDisclosure = { [weak self] in
            self?.accountDisclosed.toggle()
            self?.tableView.reloadData()
        }
    }

    override func tableView(
        _ tableView: UITableView,
        didSelectRowAt indexPath: IndexPath
    ) {
        tableView.deselectRow(at: indexPath, animated: false)
        let row = row(at: indexPath)
        if case .section(let section) = row {
            select(section)
        }
        onSelect?(row)
    }
}

/// `YTGuideSectionHeader`: `section_background_guide.png` with the title in
/// `XXSmallLightFont`/`cellGuideSectionHeaderColor`, 10 pt from the left.
final class YT6GuideSectionHeader: UIView {
    private let background = UIImageView(image: YT6.stretchableImage("section_background_guide"))
    private let label = UILabel()

    init(text: String) {
        super.init(frame: CGRect(x: 0, y: 0, width: YT6.guideWidth, height: YT6.guideHeaderHeight))
        addSubview(background)
        label.font = YT6.xxSmallLightFont
        label.textColor = YT6.guideSectionHeader
        label.backgroundColor = .clear
        label.text = text
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        background.frame = bounds
        label.sizeToFit()
        label.frame.origin = CGPoint(
            x: YT6.guideHeaderPadding,
            y: ((bounds.height - label.frame.height) / 2).rounded()
        )
    }
}

/// `YTBaseGuideCell`: background plate (`cell_background_guide[_selected]`,
/// `_tap` while pressed), 35 pt icon at (7, 10), title 10 pt right of it,
/// 168 wide, `XLargeLightFont`, gray / white when selected.
final class YT6GuideCell: UITableViewCell {
    struct Content {
        var title: String
        var icon: String?
        var selected = false
        var disclosure: String?
    }

    static let reuseID = "YT6GuideCell"

    var onDisclosure: (() -> Void)?
    private let plate = UIImageView()
    private let icon = UIImageView()
    private let title = UILabel()
    private let disclosureButton = UIButton(type: .custom)
    private var isEntrySelected = false

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = YT6.guideBackground
        backgroundView = plate
        icon.contentMode = .center
        contentView.addSubview(icon)
        title.font = YT6.xLargeLightFont
        title.backgroundColor = .clear
        contentView.addSubview(title)
        disclosureButton.addTarget(self, action: #selector(tapDisclosure), for: .touchUpInside)
        contentView.addSubview(disclosureButton)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func configure(_ content: Content) {
        isEntrySelected = content.selected
        title.text = content.title
        icon.image = content.icon.flatMap { YT6.image(content.selected ? $0 + "_selected" : $0) }
        disclosureButton.setImage(content.disclosure.flatMap(YT6.image), for: .normal)
        disclosureButton.isHidden = content.disclosure == nil
        onDisclosure = nil
        updatePressedAppearance()
        setNeedsLayout()
    }

    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        updatePressedAppearance()
    }

    /// `-[YTBaseGuideCell updatePressedAppearance]` @5c8cc.
    private func updatePressedAppearance() {
        plate.image = YT6.stretchableImage(
            isHighlighted ? "cell_background_guide_tap"
                : isEntrySelected ? "cell_background_guide_selected" : "cell_background_guide"
        )
        title.textColor = isEntrySelected ? YT6.guideTitleSelected : YT6.guideTitle
    }

    @objc
    private func tapDisclosure() {
        onDisclosure?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = YT6.guideIconSize
        icon.frame = CGRect(origin: YT6.guideIconOrigin, size: CGSize(width: size, height: size))
        let lineHeight = title.font.lineHeight.rounded(.up)
        title.frame = CGRect(
            x: icon.frame.maxX + YT6.guideTitleGap,
            y: (icon.frame.midY - lineHeight / 2).rounded(),
            width: YT6.guideTitleWidth,
            height: lineHeight
        )
        // APPROXIMATION: disclosure button right-aligned in a 44 pt square.
        disclosureButton.frame = CGRect(
            x: YT6.guideWidth - 44, y: (bounds.height - 44) / 2, width: 44, height: 44
        )
    }
}
