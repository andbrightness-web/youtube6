import UIKit

/// The playlist panel of `YTWatchView_iPhone` in place of upstream's queue
/// strip (`QueueBarView`) and queue panel (owner: «вырезать»). Shown while a
/// queue plays: 51 pt under the player with the details table moved down
/// by as much (`layoutSubviews` @7d798–7d836); open, the list covers
/// everything under the player (`setVideoListExpanded:animated:` @7dc7e,
/// 0.3 s). The data is upstream's `PlaybackQueue`.
extension WatchViewController {
    /// @7dc7e.
    private static let videoListAnimation: TimeInterval = 0.3

    func yt6BuildVideoList(_ chrome: YT6WatchChrome) {
        let list = chrome.videoList
        list.translatesAutoresizingMaskIntoConstraints = false
        list.isHidden = true
        view.addSubview(list)
        let height = list.heightAnchor.constraint(equalToConstant: YT6VideoListView.titleBarHeight)
        chrome.videoListHeight = height
        chrome.videoListBottom = list.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: playerContainer.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            height
        ])
        yt6WireVideoList(list)
    }

    private func yt6WireVideoList(_ list: YT6VideoListView) {
        list.onToggle = { [weak self] in
            guard let self, let chrome = self.yt6 else {
                return
            }
            self.yt6SetVideoListExpanded(!chrome.videoListExpanded, animated: true)
        }
        // APPROXIMATION: whether 2.0.0 folds the list after a pick is not
        // read; folding shows the new video's page.
        list.onSelect = { [weak self] video in
            self?.yt6SetVideoListExpanded(false, animated: true)
            self?.navigateTo(video)
        }
        list.onLoadMore = { [weak self] in
            self?.loadMoreQueue()
        }
        list.onMenu = { [weak self] video, anchor in
            guard let self else {
                return
            }
            VideoActionMenu.present(video: video, from: self, anchor: anchor)
        }
    }

    /// `updateQueueBar` in youtube6: the panel instead of the strip, and the
    /// page's bottom inset left to the action bar.
    func yt6UpdateVideoList() {
        guard let chrome = yt6 else {
            return
        }
        queueBar.isHidden = true
        let hasQueue = !queue.videos.isEmpty
        videoPlayerView?.loopButton.isHidden = hasQueue
        let isLandscape = view.bounds.width > view.bounds.height
        let show = hasQueue && !isPlayerFullscreen && !isLandscape
        chrome.videoList.isHidden = !show
        let top = show ? YT6VideoListView.titleBarHeight : 0
        if scrollTopToPlayerConstraint?.constant != top {
            scrollTopToPlayerConstraint?.constant = top
        }
        guard show else {
            if chrome.videoListExpanded {
                yt6SetVideoListExpanded(false, animated: false)
            }
            return
        }
        chrome.videoList.configure(
            title: queue.playlistTitle ?? "player.menu.queue".localized,
            videos: queue.videos,
            currentIndex: queue.currentIndex
        )
    }

    /// `setVideoListExpanded:animated:` @7dc7e.
    func yt6SetVideoListExpanded(_ expanded: Bool, animated: Bool) {
        guard let chrome = yt6 else {
            return
        }
        chrome.videoListExpanded = expanded
        chrome.videoListHeight?.isActive = !expanded
        chrome.videoListBottom?.isActive = expanded
        chrome.videoList.setExpanded(expanded)
        view.bringSubviewToFront(chrome.videoList)
        let apply = { self.view.layoutIfNeeded() }
        if animated {
            UIView.animate(withDuration: Self.videoListAnimation, animations: apply)
        } else {
            apply()
        }
        if expanded {
            chrome.videoList.scrollToCurrent()
        }
    }
}
