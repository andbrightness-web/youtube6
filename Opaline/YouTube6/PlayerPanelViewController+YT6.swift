import UIKit

extension YT6 {
    /// `-[YTWatchView_iPhone collapsedPlayerSize]` @7e172: a 170×100 box in
    /// the bottom-right corner (`-[YTContentView watchViewOriginForLayout:
    /// isRelative:]` @60d4c) holding the 160×90 video 5 pt from its left
    /// (`playerViewFrame` @7e5fc) — so 5 pt from the right edge and 10 pt
    /// from the bottom.
    static let collapsedPlayerWidth: CGFloat = 160
    static let collapsedPlayerRight: CGFloat = 5
    static let collapsedPlayerBottom: CGFloat = 10

    /// Mini player trailing constant in `MainTabBarController`.
    static var miniTrailing: CGFloat {
        isEnabled ? -collapsedPlayerRight : -12
    }

    /// Mini player width: upstream's third of the screen, or 2.0.0's 160.
    static func miniWidth(of bar: UIView, in view: UIView) -> NSLayoutConstraint {
        isEnabled
            ? bar.widthAnchor.constraint(equalToConstant: collapsedPlayerWidth)
            : bar.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 1.0 / 3.0)
    }
}

/// 2.0.0 collapsed-player gestures (`-[YTContentView didPanWatchContainer:]`
/// @603da): drag it up to expand, fling it sideways off screen to close.
extension PlayerPanelViewController {
    func yt6HandleCollapsedPan(_ gesture: UIPanGestureRecognizer) {
        guard !isExpanded, let bar = miniBar, let space = bar.superview else {
            return
        }
        let translation = gesture.translation(in: space)
        let velocity = gesture.velocity(in: space)
        switch gesture.state {
        case .changed:
            let horizontal = abs(translation.x) > abs(translation.y)
            bar.transform = horizontal
                ? CGAffineTransform(translationX: translation.x, y: 0)
                : CGAffineTransform(translationX: 0, y: min(translation.y, 0))
            bar.alpha = horizontal ? max(0.3, 1 - abs(translation.x) / bar.bounds.width) : 1
        case .ended, .cancelled, .failed:
            yt6FinishCollapsedPan(bar: bar, translation: translation, velocity: velocity)
        default:
            break
        }
    }

    private func yt6FinishCollapsedPan(bar: UIView, translation: CGPoint, velocity: CGPoint) {
        // Thresholds from didPanWatchContainer: 800 pt/s fling or 0.5 of the
        // box; APPROXIMATION of the exact projection (0.1 s of velocity).
        let flingX = translation.x + velocity.x * 0.1
        if abs(translation.x) > abs(translation.y),
           abs(flingX) > bar.bounds.width * 0.5 || abs(velocity.x) > 800 {
            let offscreen = flingX < 0 ? -bar.frame.maxX : bar.bounds.width * 2
            UIView.animate(
                withDuration: 0.2,
                animations: {
                    bar.transform = CGAffineTransform(translationX: offscreen, y: 0)
                    bar.alpha = 0
                },
                completion: { _ in
                    self.close()
                }
            )
        } else if translation.y < -bar.bounds.height * 0.5 || velocity.y < -800 {
            expand(animated: true)
        } else {
            UIView.animate(withDuration: 0.2) {
                bar.transform = .identity
                bar.alpha = 1
            }
        }
    }
}
