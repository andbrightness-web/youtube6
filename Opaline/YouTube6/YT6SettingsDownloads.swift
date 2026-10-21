import UIKit

/// DOWNLOADS in the 2013 settings (REQUEST711). No 2.0.0 analog: a section
/// in the same style with Opaline's download choices (quality, comments,
/// captions), the space the saved videos take and "Delete All Downloads"
/// behind a confirmation.
enum YT6SettingsDownloads {
    private static var deleteAllTitle: String {
        YT6SettingsStyle.text(russian: "Удалить все загрузки", english: "Delete All Downloads")
    }

    static func section(_ host: YT6SettingsViewController) -> YT6SettingsSection {
        let used = YT6SettingsRow(
            title: YT6SettingsStyle.text(russian: "Занято", english: "Used Space"),
            detail: DownloadMenu.sizeText(DownloadStore.yt6TotalBytes())
        )
        var deleteAll = YT6SettingsRow(title: deleteAllTitle) { [weak host] in
            host.map(confirmDeleteAll)
        }
        deleteAll.kind = .button
        return YT6SettingsSection(
            title: YT6SettingsStyle.header("settings.section.downloads"),
            rows: host.opaline(.downloads, [.downloadQuality, .downloadComments, .downloadCaptions])
                + [used, deleteAll]
        )
    }

    private static func confirmDeleteAll(_ host: YT6SettingsViewController) {
        let alert = UIAlertController(
            title: deleteAllTitle + "?",
            message: YT6SettingsStyle.text(
                russian: "Сохранённые видео будут удалены с устройства.",
                english: "Saved videos will be removed from this device."
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "common.cancel".localized, style: .cancel))
        alert.addAction(
            UIAlertAction(
                title: YT6SettingsStyle.text(russian: "Удалить", english: "Delete"),
                style: .destructive
            ) { [weak host] _ in
                DownloadStore.yt6RemoveAll()
                host?.reload()
                if let view = host?.view {
                    ToastView.show("downloads.deleted".localized, in: view)
                }
            }
        )
        host.presentOnTop(alert)
    }
}

extension DownloadStore {
    /// Bytes under the downloads folder: finished videos, their metadata
    /// and any half-done parts.
    static func yt6TotalBytes() -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys
        ) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true {
                total += Int64(values?.fileSize ?? 0)
            }
        }
        return total
    }

    /// Every saved or queued video, through Opaline's own paths: a queued
    /// or running job is cancelled by `VideoDownloader` (which removes its
    /// folder), the rest by `remove`.
    static func yt6RemoveAll() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let downloader = VideoDownloader.shared
        for videoId in names {
            if downloader.isQueued(videoId) {
                downloader.cancel(videoId)
            } else {
                remove(videoId)
            }
        }
    }
}
