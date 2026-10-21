import UIKit

/// A video's download on its 2.0.0 row (REQUEST714). 2.0.0 had no
/// downloads, so the pieces are its own: a progress line along the bottom of
/// the thumbnail drawn with the player's scrubber artwork
/// (`player_scrubber_track` / `player_scrubber_played_track`), and the
/// state in the row's grey line — «45 %», «Queued», the size once saved.
/// It watches the download notifications itself, like upstream's
/// `DownloadProgressBar`, so no list has to know a download runs.
final class YT6DownloadBar: UIView {
    static let height: CGFloat = 4

    /// The row's grey line while there is something to say; nil restores it.
    var onText: ((String?) -> Void)?
    /// The Downloads list shows a finished video's size there.
    var showsSize = false
    private(set) var videoId: String?
    private let track = UIImageView(image: YT6.stretchableImage("player_scrubber_track"))
    private let fill = UIImageView(image: YT6.stretchableImage("player_scrubber_played_track"))
    private var fraction: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(track)
        addSubview(fill)
        isHidden = true
        for name in [DownloadStore.didChangeNotification, VideoDownloader.didProgressNotification] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(refresh),
                name: name,
                object: nil
            )
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private static func text(
        for status: DownloadStatus,
        videoId: String,
        showsSize: Bool
    ) -> String? {
        let russian = Locale.preferredLanguages.first?.hasPrefix("ru") == true
        switch status {
        case .running:
            return "\(Int((VideoDownloader.shared.progress * 100).rounded())) %"
        case .queued:
            return russian ? "В очереди" : "Queued"
        case .failed:
            return russian ? "Ошибка загрузки" : "Download failed"
        case .ready:
            guard showsSize else {
                return nil
            }
            let file = DownloadStore.videoFile(for: videoId)
            let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard bytes > 0 else {
                return nil
            }
            return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        case .none:
            return nil
        }
    }

    func follow(_ videoId: String?) {
        self.videoId = videoId
        refresh()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds
        fill.frame = CGRect(x: 0, y: 0, width: bounds.width * fraction, height: bounds.height)
    }

    @objc
    private func refresh() {
        guard let videoId else {
            isHidden = true
            onText?(nil)
            return
        }
        let status = DownloadStatus.of(videoId)
        fraction = status == .running ? CGFloat(VideoDownloader.shared.progress) : 0
        isHidden = !status.isActive
        setNeedsLayout()
        onText?(Self.text(for: status, videoId: videoId, showsSize: showsSize))
    }
}
