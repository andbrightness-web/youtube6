import UIKit

/// iOS takes a tap on a list that is still gliding as «stop», not as a tap
/// on the row under the finger. On the iPod a feed coasts on, barely
/// visibly, for a good while after a flick, and a video took two or three
/// taps to open (REQUEST705). A tap that lands while the list moves stops
/// it and opens the row anyway; taps on a resting list are left to the
/// list, and taps on a row's own buttons (the ⋮ menu) to them.
final class YT6TapThrough: NSObject, UIGestureRecognizerDelegate {
    private static var key: UInt8 = 0

    private weak var scrollView: UIScrollView?
    private var tapStoppedGlide = false

    /// Every feed and list under `root`, once.
    static func attach(under root: UIView) {
        var stack = [root]
        while let view = stack.popLast() {
            stack += view.subviews
            guard let scroll = view as? UIScrollView,
                  scroll is UICollectionView || scroll is UITableView,
                  objc_getAssociatedObject(scroll, &key) == nil
            else {
                continue
            }
            let helper = YT6TapThrough()
            helper.scrollView = scroll
            let tap = UITapGestureRecognizer(target: helper, action: #selector(tapped(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = helper
            scroll.addGestureRecognizer(tap)
            objc_setAssociatedObject(scroll, &key, helper, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        tapStoppedGlide = scrollView?.isDecelerating == true
        return tapStoppedGlide
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc
    private func tapped(_ tap: UITapGestureRecognizer) {
        guard tapStoppedGlide, tap.state == .ended, let scrollView else {
            return
        }
        tapStoppedGlide = false
        let point = tap.location(in: scrollView)
        if scrollView.hitTest(point, with: nil) is UIControl {
            return
        }
        if let list = scrollView as? UICollectionView,
           let indexPath = list.indexPathForItem(at: point) {
            guard list.delegate?.collectionView?(list, shouldSelectItemAt: indexPath) ?? true else {
                return
            }
            list.delegate?.collectionView?(list, didSelectItemAt: indexPath)
        } else if let table = scrollView as? UITableView,
                  let indexPath = table.indexPathForRow(at: point) {
            table.delegate?.tableView?(table, didSelectRowAt: indexPath)
        }
    }
}
