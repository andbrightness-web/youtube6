import UIKit

/// The 2.0.0 channel page over upstream's `ChannelViewController`: «Канал»
/// in the title bar (`YTChannelViewController_iPhone loadView` @32c9e), a
/// fixed top — banner, header bar, tab titles — and the list under it, which
/// scrolls on its own (`YTChannelView_iPhone layoutSubviews` @5ee34). Tabs:
/// VIDEOS and PLAYLISTS (`initWithUploadsView:` @5ed64/5ee04); 2.0.0's
/// ACTIVITY has no source in upstream, and its Live/Shorts tabs, sort chips,
/// About and channel search had no place in 2.0.0.
extension ChannelViewController {
    /// The tabs 2.0.0 shows, in order.
    static let yt6TabList: [ChannelTabsView.Tab] = [.videos, .playlists]

    func yt6SetupLayout(_ cv: UICollectionView) {
        title = YT6.Channel.title
        _ = YT6Chrome.replacesToolbar(in: self)
        spinner.style = .gray
        headerView.yt6Install(in: view)
        let tabs = YT6ChannelTabs(titles: [
            YT6.string("channel.videos", fallback: "VIDEOS"),
            YT6.string("channel.playlists", fallback: "PLAYLISTS")
        ])
        tabs.translatesAutoresizingMaskIntoConstraints = false
        tabs.onSelect = { [weak self] index in
            self?.yt6SelectTab(index)
        }
        // Over the list, so the titles' shadow lies on it.
        view.addSubview(tabs)
        view.addSubview(errorLabel)
        cv.translatesAutoresizingMaskIntoConstraints = false
        cv.autoresizingMask = []
        cv.contentInset = .zero
        cv.scrollIndicatorInsets = .zero
        NSLayoutConstraint.activate(yt6Constraints(cv, tabs: tabs))
        headerView.subscribeButton.addTarget(
            self,
            action: #selector(subscribeButtonTapped),
            for: .touchUpInside
        )
        yt6UpdateEmptyText()
        YT6PullRefresh.attach(under: view)
        YT6TapThrough.attach(under: view)
    }

    /// `YTFeedTableStatusView` (light) @3e9036/3e905e: `XLargeLightFont`,
    /// `mediumTextColor`.
    func yt6StyleErrorLabel() {
        errorLabel.font = YT6.Channel.statusFont
        errorLabel.textColor = YT6.Watch.medium
    }

    private func yt6SelectTab(_ index: Int) {
        guard Self.yt6TabList.indices.contains(index) else {
            return
        }
        selectTab(Self.yt6TabList[index])
        yt6UpdateEmptyText()
    }

    /// `status.empty.channel_videos` @30e60 / `channel_playlists` @5edb4.
    /// APPROXIMATION: upstream shows the same label when loading failed,
    /// where 2.0.0 said `error.channel`.
    private func yt6UpdateEmptyText() {
        errorLabel.text = currentTab == .playlists
            ? YT6.string("status.empty.channel_playlists", fallback: "No playlists")
            : YT6.string("status.empty.channel_videos", fallback: "No videos")
    }

    private func yt6Constraints(_ cv: UICollectionView, tabs: UIView) -> [NSLayoutConstraint] {
        [
            tabs.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tabs.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabs.heightAnchor.constraint(equalToConstant: YT6ChannelTabs.height),
            cv.topAnchor.constraint(equalTo: tabs.bottomAnchor),
            cv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            cv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            errorLabel.centerXAnchor.constraint(equalTo: cv.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: cv.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            errorLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
        ]
    }
}

extension ChannelHeaderView {
    var yt6Header: YT6ChannelHeader? {
        subviews.lazy.compactMap { $0 as? YT6ChannelHeader }.first
    }

    /// Replaces `install(in:collectionView:errorLabel:)`: upstream's banner,
    /// avatar, labels and button restyled and laid out by `YT6ChannelHeader`.
    func yt6Install(in parent: UIView) {
        yt6Restyle()
        let header = YT6ChannelHeader(parts: YT6ChannelHeader.Parts(
            banner: bannerImageView,
            shadow: separatorView,
            avatar: avatarView,
            name: nameLabel,
            subscribers: subscribersLabel,
            button: subscribeButton
        ))
        header.frame = bounds
        header.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(header)
        parent.addSubview(self)
        let height = heightAnchor.constraint(equalToConstant: header.preferredHeight)
        header.heightConstraint = height
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: parent.safeAreaLayoutGuide.topAnchor),
            leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            height
        ])
    }

    private func yt6Restyle() {
        bannerOverlay.removeFromSuperview()
        // APPROXIMATION: 2.0.0 scales its branding banner to fill
        // (contentMode 0 @5f19a); today's banners have another aspect.
        bannerImageView.contentMode = .scaleAspectFill
        bannerImageView.image = YT6.image("channel_default_background")
        separatorView.backgroundColor = YT6.Channel.bannerShadow
        avatarView.layer.cornerRadius = 0
        avatarView.layer.borderWidth = 0
        // APPROXIMATION: a flat light gray for `thumbnail_placeholder_light`.
        avatarView.backgroundColor = UIColor(white: 0.85, alpha: 1)
        nameLabel.font = YT6.Channel.titleFont
        nameLabel.textColor = YT6.Watch.xDark
        subscribersLabel.font = YT6.smallLightFont
        subscribersLabel.textColor = YT6.Watch.medium
        YT6SubscribeSwitch.prepare(subscribeButton)
    }

    /// After upstream's `update(with:fallback:)`: 2.0.0 shows the
    /// subscribers only — no video count, no verified badge. APPROXIMATION:
    /// YouTube's own text («1,2 млн подписчиков») rather than
    /// `channel.subscribers` «Подписчиков: %@» (@3fd55a).
    func yt6Update(with info: ChannelInfo) {
        subscribersLabel.text = info.subscriberCountText
        verifiedBadgeView.isHidden = true
        yt6Header?.hasBanner = info.bannerURL != nil
    }

    /// Replaces `applyTheme(isSubscribed:)`. While a (un)subscribe request
    /// runs upstream disables the button: that is the switch's state 1.
    func yt6ApplyStyle(isSubscribed: Bool) {
        backgroundColor = YT6VideoRow.background
        guard let header = yt6Header else {
            return
        }
        var state = YT6SubscribeSwitch.State.off
        if !subscribeButton.isEnabled, !OAuthClient.shared.isAnonymous {
            state = .busy
        } else if isSubscribed {
            state = .on
        }
        YT6SubscribeSwitch.apply(state, to: subscribeButton, spinner: header.spinner)
        header.setNeedsLayout()
    }
}

extension VideosViewController {
    /// Row height of a channel's Playlists tab: `YTPlaylistCell_iPhone`
    /// cards (`YTChannelView_iPhone initWithUploadsView:` @5eda4).
    var yt6ChannelRowHeight: CGFloat? {
        guard let channel = self as? ChannelViewController, channel.currentTab == .playlists else {
            return nil
        }
        return YT6PlaylistCard.height
    }

    /// The card cell for a channel's Playlists tab; nil elsewhere.
    func yt6ChannelCell(
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell? {
        guard let channel = self as? ChannelViewController, channel.currentTab == .playlists else {
            return nil
        }
        let reuseId = YT6PlaylistItemCell.reuseId
        collectionView.register(YT6PlaylistItemCell.self, forCellWithReuseIdentifier: reuseId)
        let dequeued = collectionView.dequeueReusableCell(
            withReuseIdentifier: reuseId,
            for: indexPath
        )
        guard let cell = dequeued as? YT6PlaylistItemCell else {
            return dequeued
        }
        if !isLoadingInitial, let playlist = channel.playlistLookup[video(at: indexPath).id] {
            cell.card.configure(with: playlist)
        }
        return cell
    }
}
