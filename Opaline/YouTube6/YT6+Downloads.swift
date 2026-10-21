import UIKit

/// Downloads in the 2013 dress (REQUEST711). 2.0.0 could not save videos,
/// so these lean on its look: «Save to iPod» in the action sheets, a
/// «Downloads» row in the guide's account group, settings in Settings.
extension YT6 {
    /// «Download» in the menus, as 2013 would have said it.
    static var saveToDeviceTitle: String {
        let russian = YT6.isRussianInterface
        return russian ? "Сохранить на iPod" : "Save to iPod"
    }

    /// While a download runs: «Cancel download (45 %)» (REQUEST714).
    static var cancelDownloadTitle: String {
        let russian = YT6.isRussianInterface
        let percent = Int((VideoDownloader.shared.progress * 100).rounded())
        return russian ? "Отменить загрузку (\(percent) %)" : "Cancel download (\(percent) %)"
    }

    static var deleteDownloadTitle: String {
        let russian = YT6.isRussianInterface
        return russian ? "Удалить с iPod" : "Delete from iPod"
    }

    /// Downloads saving or waiting, for the guide row's count.
    static var activeDownloads: Int {
        VideoDownloader.shared.isDownloading ? VideoDownloader.shared.queuedCount + 1 : 0
    }

    /// The guide row's icon: 2.0.0 has no download glyph. APPROXIMATION:
    /// `uploads_guide` (arrow up over a bar, 35 pt) with the arrow turned
    /// down — the arrow fills 10–20 pt of its height, the bar stays.
    static func downloadsGuideIcon(selected: Bool) -> UIImage? {
        guard let uploads = image(selected ? "uploads_guide_selected" : "uploads_guide") else {
            return nil
        }
        let size = uploads.size
        let band = CGRect(x: 0, y: 10, width: size.width, height: 10)
        let format = UIGraphicsImageRendererFormat()
        format.scale = uploads.scale
        let icon = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let rect = CGRect(origin: .zero, size: size)
            context.cgContext.saveGState()
            let below = CGRect(x: 0, y: band.maxY, width: size.width, height: size.height)
            context.cgContext.clip(to: [below])
            uploads.draw(in: rect)
            context.cgContext.restoreGState()
            context.cgContext.saveGState()
            context.cgContext.clip(to: band)
            // Mirror the band in place: y -> band.minY + band.maxY - y.
            context.cgContext.translateBy(x: 0, y: band.minY + band.maxY)
            context.cgContext.scaleBy(x: 1, y: -1)
            uploads.draw(in: rect)
            context.cgContext.restoreGState()
        }
        return icon.withRenderingMode(.alwaysOriginal)
    }
}

/// The Downloads list on 2.0.0's light background like every other list —
/// upstream paints it with the app theme, black in dark mode (REQUEST716);
/// the empty text as 2.0.0's empty lists (16 Light #999, @3e9036).
extension DownloadsViewController {
    func yt6ApplyListChrome(table: UITableView, empty: UILabel) {
        view.backgroundColor = YT6VideoRow.background
        table.backgroundColor = YT6VideoRow.background
        table.separatorColor = .clear
        empty.font = YT6.xLargeLightFont
        empty.textColor = YT6.guideTitle
    }
}
