import UIKit

/// Feeds (`VideosViewController`: What To Watch, Live, the categories,
/// channels) as 2.0.0 lists: full-width 95 pt rows of `YT6FeedCell` on the
/// light background, no grid, no rails.
extension VideosViewController {
    func yt6UpdateItemSize() {
        guard let collectionView,
              let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout
        else {
            return
        }
        collectionView.backgroundColor = YT6VideoRow.background
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        let size = CGSize(width: collectionView.bounds.width, height: YT6VideoRow.height)
        if layout.itemSize != size {
            layout.itemSize = size
            layout.invalidateLayout()
        }
    }

    func yt6Cell(
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell {
        collectionView.register(YT6FeedCell.self, forCellWithReuseIdentifier: YT6FeedCell.reuseId)
        let dequeued = collectionView.dequeueReusableCell(
            withReuseIdentifier: YT6FeedCell.reuseId,
            for: indexPath
        )
        guard let cell = dequeued as? YT6FeedCell else {
            return dequeued
        }
        if isLoadingInitial {
            cell.row.configureSkeleton()
            return cell
        }
        let video = video(at: indexPath)
        cell.row.configure(with: video)
        cell.row.onMenuTap = { [weak self] anchor in
            self?.presentVideoMenu(video, anchor: anchor)
        }
        return cell
    }
}

extension YT6 {
    /// The list cell class tables register (`SubscriptionVideoCell` upstream).
    static var listCellClass: SubscriptionVideoCell.Type {
        isEnabled ? YT6ListVideoCell.self : SubscriptionVideoCell.self
    }
}
