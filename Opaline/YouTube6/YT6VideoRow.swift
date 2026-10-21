import UIKit

/// The row of `YTVideoCell_iPhone`, shared by the feed (collection) and list
/// (table) cells.
///
/// `-[YTVideoCell_iPhone layoutSubviews]` @3df17c: thumbnail 123×70 centered
/// vertically, 12 pt from the left (@3df262/3df276, @3df1e8); text to its
/// right, 16 pt from the right edge (@3df2d0); title two lines, uploader and
/// views right under it (@3df49a); duration badge in the thumbnail's
/// bottom-right corner (@3df6d2). `updateBackground` @3df8f4: title
/// `mediumLightFont` (13) in `XDarkTextColor` (51); `initWithReuseIdentifier:`
/// @3ded60: the other lines `smallLightFont` (12) in `mediumTextColor` (153).
final class YT6VideoRow: UIView {
    /// `+[YTVideoCell_iPhone cellHeight]` @3dfcca.
    static let height: CGFloat = 95
    static let thumbnailSize = CGSize(width: 123, height: 70)
    static let thumbnailLeft: CGFloat = 12
    static let textGap: CGFloat = 12
    static let textRight: CGFloat = 16
    /// `+[UIColor backgroundColor]` @3f5532 — around the cards.
    static let background = UIColor(white: 237 / 255, alpha: 1)

    var onMenuTap: ((UIView) -> Void)?

    private let plate = UIImageView()
    let thumbnail = ThumbnailImageView(frame: .zero)
    private let duration = UILabel()
    private let title = UILabel()
    private let uploader = UILabel()
    private let meta = UILabel()
    private let menu = UIButton(type: .custom)
    let download = YT6DownloadBar()
    private var plainMeta: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Self.background
        // APPROXIMATION: every row on a middle card plate; 2.0.0 picks
        // top/middle/bottom by the row's place in its section.
        plate.image = YT6.stretchableImage("grouped_table_card_middle")
        addSubview(plate)
        thumbnail.contentMode = .scaleAspectFill
        thumbnail.clipsToBounds = true
        thumbnail.backgroundColor = UIColor(white: 0.85, alpha: 1)
        addSubview(thumbnail)
        setUpLabels()
        // `overflow.png` 21×21, top right 10/4 (`YTBaseVideoCell`); 2.0.0
        // showed it only on iPad and opened the sheet on a long press on
        // iPhone — both here (REQUEST710).
        menu.setImage(YT6.image("overflow"), for: .normal)
        menu.addTarget(self, action: #selector(tapMenu), for: .touchUpInside)
        addSubview(menu)
        addGestureRecognizer(
            UILongPressGestureRecognizer(target: self, action: #selector(pressMenu(_:)))
        )
        setUpDownload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    private func setUpDownload() {
        thumbnail.addSubview(download)
        download.onText = { [weak self] text in
            self?.meta.text = text ?? self?.plainMeta
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        plate.frame = bounds
        let size = Self.thumbnailSize
        thumbnail.frame = CGRect(
            x: Self.thumbnailLeft,
            y: ((bounds.height - size.height) / 2).rounded(),
            width: size.width,
            height: size.height
        )
        menu.frame = CGRect(x: bounds.width - 4 - 21 - 11.5, y: 10 - 11.5, width: 44, height: 44)
        let left = thumbnail.frame.maxX + Self.textGap
        let width = bounds.width - left - Self.textRight - 16
        let fit = CGSize(width: width, height: .greatestFiniteMagnitude)
        title.frame.size = title.sizeThatFits(fit)
        title.frame.size.width = width
        let lines = [title, uploader, meta]
        uploader.frame.size = CGSize(width: width, height: uploader.font.lineHeight.rounded(.up))
        meta.frame.size = CGSize(width: width, height: meta.font.lineHeight.rounded(.up))
        let total = lines.reduce(0) { $0 + $1.frame.height }
        var y = ((bounds.height - total) / 2).rounded()
        for line in lines {
            line.frame.origin = CGPoint(x: left, y: y)
            y += line.frame.height
        }
        layoutThumbnailBadges()
    }

    /// The duration plate and the download line inside the thumbnail.
    private func layoutThumbnailBadges() {
        duration.sizeToFit()
        duration.frame.size.width += 8
        duration.frame.origin = CGPoint(
            x: thumbnail.bounds.width - duration.frame.width - 4,
            y: thumbnail.bounds.height - duration.frame.height - 4
        )
        let line = YT6DownloadBar.height
        download.frame = CGRect(
            x: 0,
            y: thumbnail.bounds.height - line,
            width: thumbnail.bounds.width,
            height: line
        )
    }

    func configure(with video: Video) {
        YT6OriginalTitles.show(video.title, videoId: video.id, in: title)
        uploader.text = video.channelName
        meta.text = VideoCardHelper.metaText(
            viewCount: video.viewCount,
            publishedAt: video.publishedAt,
            separator: " · "
        )
        duration.text = video.isLive ? "LIVE" : video.duration
        duration.isHidden = duration.text?.isEmpty ?? true
        YT6SourceBadge.markRow(thumbnail, videoId: video.id)
        YT6AndCastChannelMap.learn(videoId: video.id, youtubeChannel: video.channelId)
        thumbnail.maxPixelSize = ThumbnailSizing.pixelSize(
            forDisplayWidth: Self.thumbnailSize.width,
            scale: UIScreen.main.scale
        )
        if let url = URL(string: video.thumbnailURL) {
            thumbnail.setImage(url: url, videoId: video.isShort ? nil : video.id)
        }
        menu.isHidden = false
        plainMeta = meta.text
        download.follow(video.id)
        setNeedsLayout()
    }

    func configureSkeleton() {
        [title, uploader, meta, duration].forEach { $0.text = nil }
        plainMeta = nil
        download.follow(nil)
        duration.isHidden = true
        menu.isHidden = true
        thumbnail.cancel()
        thumbnail.image = nil
    }

    private func setUpLabels() {
        title.numberOfLines = 2
        title.font = UIFont(name: "HelveticaNeue-Light", size: 13)
        title.textColor = UIColor(white: 51 / 255, alpha: 1)
        for label in [uploader, meta] {
            label.font = YT6.smallLightFont
            label.textColor = YT6.guideTitle
        }
        // APPROXIMATION: `YTBadge` drawn as a dark plate with white text.
        duration.font = UIFont(name: "HelveticaNeue-Bold", size: 11)
        duration.textColor = .white
        duration.textAlignment = .center
        duration.backgroundColor = UIColor(white: 0, alpha: 0.75)
        duration.layer.cornerRadius = 2
        duration.clipsToBounds = true
        thumbnail.addSubview(duration)
        [title, uploader, meta].forEach(addSubview)
    }

    @objc
    private func tapMenu() {
        onMenuTap?(menu)
    }

    @objc
    private func pressMenu(_ press: UILongPressGestureRecognizer) {
        if press.state == .began, !menu.isHidden {
            onMenuTap?(menu)
        }
    }
}

/// Feed cell (`VideosViewController`). Upstream's `VideoCell` cannot be
/// subclassed for this — its `configure(with:)` lives in an extension — and
/// configuring it would fetch the full-width thumbnail anyway.
final class YT6FeedCell: UICollectionViewCell {
    static let reuseId = "YT6FeedCell"

    let row = YT6VideoRow()

    override init(frame: CGRect) {
        super.init(frame: frame)
        row.frame = contentView.bounds
        row.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        row.configureSkeleton()
    }
}

/// List cell (subscriptions, history, playlists, search): same idea over
/// `SubscriptionVideoCell`.
final class YT6ListVideoCell: SubscriptionVideoCell {
    private let row = YT6VideoRow()

    /// The Downloads list shows a saved video's size in the grey line.
    var showsDownloadSize: Bool {
        get { row.download.showsSize }
        set { row.download.showsSize = newValue }
    }

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.subviews.forEach { $0.isHidden = true }
        row.frame = contentView.bounds
        row.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        row.onMenuTap = { [weak self] anchor in
            self?.onMenuTap?(anchor)
        }
        contentView.addSubview(row)
        backgroundColor = YT6VideoRow.background
        selectionStyle = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Upstream's prepareForReuse shows its avatar again, and not every
        // upstream view sits under the row — keep only the row visible.
        for view in contentView.subviews where view !== row {
            view.isHidden = true
        }
        contentView.bringSubviewToFront(row)
        contentView.superview?.bringSubviewToFront(contentView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        row.configureSkeleton()
    }

    override func configure(with video: Video) {
        row.configure(with: video)
    }

    override func configureSkeleton() {
        row.configureSkeleton()
    }
}
