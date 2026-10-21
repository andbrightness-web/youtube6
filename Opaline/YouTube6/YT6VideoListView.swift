import UIKit

/// `YTVideoListView` (`init` @7adf8, `layoutSubviews` @7b418): the playlist
/// panel right under the player. A 51 pt title bar (`+titleBarHeight`
/// @7b6a8) in `videoListHeaderBackgroundColor` #212121: the title in
/// `largeLightFont` (15) `XLightTextColor`, under it «N/M» (`%d/%d`,
/// `updateListPositionLabelText` @7b6dc) and 6 pt after that the author,
/// both `smallLightFont` `mediumTextColor`; `video_list_disclosure` 12 pt
/// from the right, `_selected` while open. A tap on the bar or the button
/// toggles (`didToggle:` @7b6b0); open, the list fills the rest of the
/// view (`setFrame:` @7b656) over `videoListBackgroundColor` #333333.
final class YT6VideoListView: UIView, UITableViewDataSource, UITableViewDelegate {
    static let titleBarHeight: CGFloat = 51
    static let headerBackground = UIColor(white: 33 / 255, alpha: 1)
    static let listBackground = UIColor(white: 51 / 255, alpha: 1)

    var onToggle: (() -> Void)?
    var onSelect: ((Video) -> Void)?
    var onLoadMore: (() -> Void)?
    var onMenu: ((Video, UIView) -> Void)?

    private let bar = UIView()
    private let titleLabel = UILabel()
    private let positionLabel = UILabel()
    private let authorLabel = UILabel()
    private let disclosure = UIButton(type: .custom)
    private let list = UITableView(frame: .zero, style: .plain)
    private var videos: [Video] = []
    private var currentIndex = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        bar.backgroundColor = Self.headerBackground
        titleLabel.font = UIFont(name: "HelveticaNeue-Light", size: 15)
        titleLabel.textColor = .white
        for label in [positionLabel, authorLabel] {
            label.font = YT6.smallLightFont
            label.textColor = YT6.Watch.medium
        }
        disclosure.setImage(YT6.image("video_list_disclosure"), for: .normal)
        disclosure.setImage(YT6.image("video_list_disclosure_selected"), for: .selected)
        disclosure.addTarget(self, action: #selector(toggle), for: .touchUpInside)
        bar.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggle)))
        [titleLabel, positionLabel, authorLabel, disclosure].forEach(bar.addSubview)
        setUpList()
        addSubview(list)
        addSubview(bar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// `setTitle:author:currentIndex:videoCount:` @7b280.
    /// APPROXIMATION: upstream's queue has no playlist owner, so the author
    /// is left empty.
    func configure(title: String, videos: [Video], currentIndex: Int) {
        titleLabel.text = title
        authorLabel.text = nil
        positionLabel.text = "\(currentIndex + 1)/\(videos.count)"
        let changed = videos.map(\.id) != self.videos.map(\.id) || currentIndex != self.currentIndex
        self.videos = videos
        self.currentIndex = currentIndex
        if changed {
            list.reloadData()
        }
        setNeedsLayout()
    }

    /// `setDisclosureButtonSelected:` @7b688.
    func setExpanded(_ expanded: Bool) {
        disclosure.isSelected = expanded
    }

    func scrollToCurrent() {
        guard videos.indices.contains(currentIndex) else {
            return
        }
        layoutIfNeeded()
        list.scrollToRow(at: IndexPath(row: currentIndex, section: 0), at: .middle, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width
        let barHeight = Self.titleBarHeight
        bar.frame = CGRect(x: 0, y: 0, width: width, height: barHeight)
        disclosure.sizeToFit()
        disclosure.center = CGPoint(
            x: width - YT6.Watch.padding - disclosure.bounds.width / 2,
            y: barHeight / 2
        )
        let textWidth = width - disclosure.bounds.width - 36
        let titleHeight = titleLabel.font.lineHeight.rounded(.up)
        titleLabel.frame.size = CGSize(width: textWidth, height: titleHeight)
        positionLabel.sizeToFit()
        let lines = titleLabel.frame.height + positionLabel.frame.height
        titleLabel.frame.origin = CGPoint(x: 12, y: (25.5 - lines / 2).rounded(.down))
        positionLabel.frame.origin = CGPoint(x: 12, y: titleLabel.frame.maxY)
        authorLabel.frame = CGRect(
            x: positionLabel.frame.maxX + 6,
            y: positionLabel.frame.minY,
            width: max(textWidth - positionLabel.frame.width - 6, 0),
            height: positionLabel.frame.height
        )
        list.frame = CGRect(x: 0, y: barHeight, width: width, height: bounds.height - barHeight)
    }

    private func setUpList() {
        list.backgroundColor = Self.listBackground
        list.separatorStyle = .none
        list.rowHeight = YT6VideoRow.height
        list.dataSource = self
        list.delegate = self
        list.register(YT6VideoListCell.self, forCellReuseIdentifier: YT6VideoListCell.reuseId)
    }

    @objc
    private func toggle() {
        onToggle?()
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        videos.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: YT6VideoListCell.reuseId,
            for: indexPath
        )
        guard let row = cell as? YT6VideoListCell, let video = videos[safe: indexPath.row] else {
            return cell
        }
        row.configure(
            video,
            number: indexPath.row == currentIndex ? nil : indexPath.row + 1,
            position: YT6VideoListCell.position(of: indexPath.row, in: videos.count)
        )
        row.onMenuTap = { [weak self] anchor in
            self?.onMenu?(video, anchor)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if let video = videos[safe: indexPath.row] {
            onSelect?(video)
        }
    }

    func tableView(
        _ tableView: UITableView,
        willDisplay cell: UITableViewCell,
        forRowAt indexPath: IndexPath
    ) {
        if indexPath.row >= videos.count - 4 {
            onLoadMore?()
        }
    }
}
