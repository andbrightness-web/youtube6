import UIKit

/// The guide table (`YTGuideTableView` + `YTBaseGuideCell`/`YTGuideCell_iPhone`
/// + `YTGuideSectionHeader`).
///
/// Sections, in 2.0.0 order: ACCOUNT (Sign In / the account, with Watch
/// Later, History, Playlists and Liked disclosed under it), What To Watch and
/// My Subscriptions, FROM YOUTUBE (Live and categories), Settings.
final class YT6GuideViewController: UITableViewController {
    enum Row: Equatable {
        case account
        case section(YT6Section)
        /// A subscribed channel, by index into `channels`.
        case channel(Int)
        case settings
    }

    var onSelect: ((Row) -> Void)?
    private(set) var selectedSection: YT6Section = .whatToWatch
    /// `YTGuideTableView showSubscriptionsSection`: the subscribed channels,
    /// listed under My Subscriptions.
    private(set) var channels: [SubscribedChannel] = []
    private var selectedChannelId: String?
    /// `-[YTGuideTableView toggleDiscloseAccount]`.
    private var accountDisclosed = true

    private var channelRows: [Row] {
        channels.indices.map(Row.channel)
    }

    private var sections: [(header: String?, rows: [Row])] {
        let signedIn = OAuthClient.shared.isSignedIn
        var account: [Row] = [.account]
        if signedIn, accountDisclosed {
            account += YT6Section.allCases.filter(\.needsAccount).map(Row.section)
        }
        // Saved videos play without an account and without a network.
        account.append(.section(.downloads))
        return [
            (YT6.string("guide_section.account", fallback: "ACCOUNT"), account),
            (nil, [Row.section(.whatToWatch), .section(.subscriptions)] + channelRows),
            (
                YT6.string("guide_section.from_youtube", fallback: "FROM YOUTUBE"),
                YT6Section.fromYouTube.map(Row.section)
            ),
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
        reloadChannels()
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

    /// Channels from upstream's cache; fetched once when there are none.
    func reloadChannels() {
        channels = AppCache.shared.subscribedChannels ?? []
        tableView.reloadData()
        guard channels.isEmpty, OAuthClient.shared.isSignedIn else {
            return
        }
        ServiceContainer.subscribedChannels.fetchSubscribedChannels { [weak self] result in
            guard case .success(let fetched) = result else {
                return
            }
            DispatchQueue.main.async {
                AppCache.shared.setSubscribedChannels(fetched)
                self?.channels = fetched
                self?.tableView.reloadData()
            }
        }
    }

    func select(_ section: YT6Section) {
        selectedSection = section
        selectedChannelId = nil
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
                    selected: section == selectedSection && selectedChannelId == nil
                )
            )
        case .channel(let index):
            configureChannel(guideCell, channels[index])
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

    private func configureChannel(_ cell: YT6GuideCell, _ channel: SubscribedChannel) {
        cell.configure(
            YT6GuideCell.Content(
                title: channel.title,
                selected: channel.id == selectedChannelId,
                avatarURL: channel.avatarURL
            )
        )
    }

    private func configureAccount(_ cell: YT6GuideCell) {
        let signedIn = OAuthClient.shared.isSignedIn
        let loggedIn = UserProfileStore.shared.displayName
            ?? YT6.string("guide.account_loggedin.access", fallback: "Your account")
        cell.configure(
            YT6GuideCell.Content(
                title: signedIn ? loggedIn : YT6.string("guide.account", fallback: "Sign In"),
                disclosure: signedIn ? (accountDisclosed ? "collapse_guide" : "expand_guide") : nil,
                photo: signedIn ? UserProfileStore.shared.avatarImage : nil
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
        } else if case .channel(let index) = row {
            selectedChannelId = channels[index].id
            tableView.reloadData()
        }
        onSelect?(row)
    }
}
