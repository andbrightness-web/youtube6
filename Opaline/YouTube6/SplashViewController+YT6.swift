import UIKit

/// The in-app splash shows 2.0.0's launch image exactly where
/// `YT6LaunchScreen.storyboard` puts it — under the status bar, on its
/// 51 gray — so the system launch screen hands over without a change.
extension SplashViewController {
    func yt6SetupLaunchImage() {
        view.backgroundColor = UIColor(white: 51 / 255, alpha: 1)
        let image = UIImageView(image: UIImage(named: "yt6_launch"))
        image.contentMode = .scaleAspectFill
        image.clipsToBounds = true
        let width = UIScreen.main.bounds.width
        image.frame = CGRect(x: 0, y: 20, width: width, height: width * 1_116 / 640)
        image.autoresizingMask = [.flexibleWidth]
        view.addSubview(image)
    }
}
