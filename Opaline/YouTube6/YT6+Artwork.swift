import UIKit

extension YT6 {
    /// The lock screen player of iOS 6 mode draws square album artwork and
    /// cut a video's 16:9 frame down to its middle (REQUEST706). The whole
    /// frame goes out centred on a black square instead, so every surface
    /// that shows now-playing artwork (lock screen, Control Center) keeps it
    /// uncropped.
    static func squareArtwork(_ image: UIImage) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0, size.width != size.height else {
            return image
        }
        let side = max(size.width, size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let canvas = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: canvas))
            let origin = CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2)
            image.draw(in: CGRect(origin: origin, size: size))
        }
    }
}
