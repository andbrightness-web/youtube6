import UIKit

/// REQUEST712/714: the flag of `YTLikesDislikesView` (@6b94c, 21×21 at the
/// right of the likes row) does nothing in upstream — there is no «report» —
/// so its place holds upstream's download button, drawn in the likes'
/// manner: not saved — an arrow over a line in #999; running — a thin ring,
/// #CCCCCC track and #1B7FCC fill, with a stop square (a tap cancels);
/// saved — the donor's `subscribed` check. The logic stays upstream's
/// (`downloadTapped`, `updateDownloadButton`, the store's notifications).
extension WatchViewController {
    private static let downloadSize = CGSize(width: 21, height: 21)
    private static let ringTrack = UIColor(white: 204 / 255, alpha: 1)

    /// «Save to iPod» — the name the downloads menu carries in youtube6.
    var yt6SaveToDeviceTitle: String {
        YT6.isRussianInterface
            ? "Сохранить на iPod"
            : "Save to iPod"
    }

    /// APPROXIMATION: no download picture in 2.0.0; a stroked arrow down over
    /// a line, 1.5 pt like the outline of `like.png`.
    private static func yt6ArrowImage() -> UIImage {
        UIGraphicsImageRenderer(size: downloadSize).image { _ in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 10.5, y: 3))
            path.addLine(to: CGPoint(x: 10.5, y: 14))
            path.move(to: CGPoint(x: 6, y: 9.5))
            path.addLine(to: CGPoint(x: 10.5, y: 14))
            path.addLine(to: CGPoint(x: 15, y: 9.5))
            path.move(to: CGPoint(x: 4, y: 18))
            path.addLine(to: CGPoint(x: 17, y: 18))
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            YT6.Watch.medium.setStroke()
            path.stroke()
        }
    }

    /// APPROXIMATION: the ring is drawn, not a donor picture.
    private static func yt6RingImage(progress: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: downloadSize).image { _ in
            let center = CGPoint(x: 10.5, y: 10.5)
            let track = UIBezierPath(
                arcCenter: center,
                radius: 8.5,
                startAngle: 0,
                endAngle: .pi * 2,
                clockwise: true
            )
            track.lineWidth = 1.5
            ringTrack.setStroke()
            track.stroke()
            let start = -CGFloat.pi / 2
            let fill = UIBezierPath(
                arcCenter: center,
                radius: 8.5,
                startAngle: start,
                endAngle: start + .pi * 2 * min(max(progress, 0), 1),
                clockwise: true
            )
            fill.lineWidth = 1.5
            YT6.Watch.link.setStroke()
            fill.stroke()
            YT6.Watch.link.setFill()
            UIBezierPath(rect: CGRect(x: 8, y: 8, width: 5, height: 5)).fill()
        }
    }
    /// The button in the flag's place, its upstream stack constraints gone.
    func yt6AdoptDownloadButton() {
        downloadButton.removeFromSuperview()
        NSLayoutConstraint.deactivate(downloadButton.constraints.filter { $0.secondItem == nil })
        downloadButton.accessibilityLabel = yt6SaveToDeviceTitle
        downloadButton.tintColor = YT6.Watch.medium
    }

    /// `updateDownloadButton` in youtube6: one picture per state.
    func yt6UpdateDownloadButton() {
        let video = watchPage?.video ?? initialVideo
        let downloader = VideoDownloader.shared
        let status = DownloadStatus.of(video.id)
        // Also run each layout pass (a new video reuses this screen): the
        // picture is redrawn only when what it shows changed.
        let state = "\(video.id) \(status) \(Int(downloader.progress * 100)) \(downloader.isMuxing)"
        guard state != yt6?.downloadState else {
            return
        }
        yt6?.downloadState = state
        let image: UIImage?
        switch status {
        case .running:
            let progress = downloader.isMuxing ? 1 : CGFloat(downloader.progress)
            image = Self.yt6RingImage(progress: progress)
        case .queued:
            image = Self.yt6RingImage(progress: 0)
        case .ready:
            image = YT6.image("subscribed")
        case .none, .failed:
            image = Self.yt6ArrowImage()
        }
        downloadButton.layer.removeAnimation(forKey: "pulse")
        downloadButton.alpha = 1
        downloadButton.setImage(image?.withRenderingMode(.alwaysOriginal), for: .normal)
    }
}
