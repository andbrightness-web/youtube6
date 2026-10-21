// swiftlint:disable file_length
import UIKit

/// The 2.0.0 watch page in portrait (`YTWatchView_iPhone`,
/// `YTVideoDetailsViewController`), built from upstream's own views so every
/// binding (titles, counts, subscribe, description, related, comments) keeps
/// working. Under the 320×180 player: the 2 pt `player_details_shadow`, then
/// cards on #EDEDED — video info (title, views, like/dislike/flag, the
/// description on tap), channel, related rows with «ДРУГИЕ ВАРИАНТЫ»,
/// «КОММЕНТАРИИ · N» with its rows (`YT6CommentsView`) — and the 51 pt
/// action bar (`YTVideoActionBarView`: add to, share) along the bottom of
/// the screen, riding away with the content while scrolling. A playing
/// queue adds the playlist panel under the player (`YT6VideoListView`).
/// Spec with addresses: ipodos27 research/YOUTUBE6-STAGE3-WATCH-2026-10-20.md.
extension YT6 {
    enum Watch {
        /// `-[YTTableViewCell layoutSubviews]` @3dd57c: content 8 pt in from
        /// both sides, the card plate 3 pt around it.
        static let cardInset: CGFloat = 8
        static let plateOutset: CGFloat = 3
        /// marginBottom 4 of one cell + marginTop 4 of the next.
        static let cardGap: CGFloat = 8
        /// `YTVideoInfoCell` paddings @79b6a…79d44.
        static let padding: CGFloat = 12
        /// Below the likes row (and below the open description).
        static let infoBottom: CGFloat = 16
        /// `YTChannelMetadataCell preferredHeight` @3ce598 (60) less margins.
        static let channelHeight: CGFloat = 52
        static let avatarSize: CGFloat = 36
        static let subscribeSize = CGSize(width: 110, height: 30)
        /// `YTCardButtonCell` / `YTCardHeaderCell preferredHeight` @3cbe7c.
        static let buttonCardHeight: CGFloat = 51
        /// `card_disclosure_arrow_*`.
        static let arrowSize: CGFloat = 20
        /// Height of `action_bar_background.png`.
        static let actionBarHeight: CGFloat = 51
        /// `setActionBarViewExpanded:animated:` @7dfc0.
        static let actionBarAnimation: TimeInterval = 0.3
        /// `startActionBarExpansionTimer` @5a7a4.
        static let actionBarReturnDelay: TimeInterval = 4
        /// `YTPlayerOverlayView layoutSubviews` @3b85a8.
        static let collapseInset: CGFloat = 8
        /// `like.png` / `dislike.png` / `flag.png`.
        static let likeSize: CGFloat = 21

        static let xDark = UIColor(white: 51 / 255, alpha: 1)
        static let dark = UIColor(white: 102 / 255, alpha: 1)
        static let medium = UIColor(white: 153 / 255, alpha: 1)
        /// `+[UIColor linkColor]` / `moreButtonTextColor`.
        static let link = UIColor(red: 27 / 255, green: 127 / 255, blue: 204 / 255, alpha: 1)
        /// `action_bar_vertical_separator.png` is a 1×1 #DDDDDD pattern.
        static let actionSeparator = UIColor(white: 221 / 255, alpha: 1)
    }
}

/// Views the 2.0.0 page adds around upstream's, and the action bar's
/// scroll-tracking state (`YTWatchViewController_iPhone` @581a4…5a7a4).
final class YT6WatchChrome: NSObject {
    let infoPlate = YT6WatchChrome.plate()
    let channelPlate = YT6WatchChrome.plate()
    let moreCard = UIButton(type: .custom)
    let commentsCard = UIButton(type: .custom)
    let commentsTitle = UILabel()
    let commentsArrow = UIImageView(image: YT6.image("card_disclosure_arrow_collapsed"))
    let disclosure = UIImageView()
    let separator = UIImageView(image: YT6.stretchableImage("horizontal_separator"))
    let comments = YT6CommentsView()
    var commentsExpanded = false
    var commentsVideoId = ""
    var commentsState = ""
    var downloadState = ""
    let videoList = YT6VideoListView()
    var videoListExpanded = false
    var videoListHeight: NSLayoutConstraint?
    var videoListBottom: NSLayoutConstraint?
    let detailsShadow = UIImageView(image: YT6.stretchableImage("player_details_shadow"))
    let actionBar = UIView()
    let addToButton = UIButton(type: .custom)
    let shareButton = UIButton(type: .custom)
    var descriptionBottom: NSLayoutConstraint?
    var likesBottom: NSLayoutConstraint?
    var moreHeight: NSLayoutConstraint?

    private(set) var actionBarOffset: CGFloat = 0
    private var dragStartOffset: CGFloat = 0
    private var dragStartY: CGFloat = 0
    private var returnTimer: Timer?

    static func plate() -> UIImageView {
        let plate = UIImageView(image: YT6.stretchableImage("grouped_table_card"))
        plate.translatesAutoresizingMaskIntoConstraints = false
        return plate
    }

    deinit {
        returnTimer?.invalidate()
    }
}

// MARK: - Build

extension WatchViewController {
    /// Re-parents upstream's content views into the 2.0.0 cards. Taking them
    /// off `contentView` drops all of upstream's constraints between them in
    /// one go; the handles upstream toggles later are pointed at ours or
    /// cleared, so nothing it re-activates fights this layout.
    func yt6RestyleWatch() {
        let chrome = YT6WatchChrome()
        yt6 = chrome
        contentView.subviews.forEach { $0.removeFromSuperview() }
        let likeViews: [UIView] = [likeButton, dislikeButton, likeCountLabel, dislikeCountLabel]
        for item in likeViews {
            item.removeFromSuperview()
            NSLayoutConstraint.deactivate(item.constraints.filter { $0.secondItem == nil })
        }
        channelTopToMeta = nil
        channelTopToDesc = nil
        bottomCommentsConstraint = nil
        yt6AdoptDownloadButton()
        relatedCollectionView.register(
            YT6FeedCell.self,
            forCellWithReuseIdentifier: YT6FeedCell.reuseId
        )
        yt6BuildInfoCard(chrome)
        yt6BuildChannelCard(chrome)
        yt6BuildRelatedAndComments(chrome)
        yt6BuildActionBar(chrome)
        yt6BuildVideoList(chrome)
        yt6BuildDetailsShadow(chrome)
        yt6ApplyColors()
    }

    private func yt6Add(_ views: [UIView], to parent: UIView) {
        for item in views {
            item.translatesAutoresizingMaskIntoConstraints = false
            parent.addSubview(item)
        }
    }

    /// `YTVideoInfoCell` @794e8/79aa0.
    private func yt6BuildInfoCard(_ chrome: YT6WatchChrome) {
        yt6Add([
            chrome.infoPlate, titleLabel, chrome.disclosure, metaLabel, chrome.separator,
            descriptionLabel, likeButton, likeCountLabel, dislikeButton, dislikeCountLabel,
            downloadButton
        ], to: contentView)
        yt6StyleInfoCard(chrome)
        let bottom = YT6.Watch.infoBottom + YT6.Watch.plateOutset
        let plateBottom = chrome.infoPlate.bottomAnchor
        chrome.likesBottom = likeButton.bottomAnchor.constraint(
            equalTo: plateBottom,
            constant: -bottom
        )
        chrome.descriptionBottom = descriptionLabel.bottomAnchor.constraint(
            equalTo: plateBottom,
            constant: -bottom
        )
        NSLayoutConstraint.activate(
            yt6InfoTextConstraints(chrome) + yt6LikesConstraints(chrome)
                + yt6PlateConstraints(chrome.infoPlate, below: contentView.topAnchor, gap: 0)
                + [chrome.likesBottom].compactMap { $0 }
        )
    }

    /// Fonts per `YTVideoInfoCell`; the title is the tap target that opens
    /// the description (@79be0).
    private func yt6StyleInfoCard(_ chrome: YT6WatchChrome) {
        titleLabel.font = YT6.xLargeLightFont
        metaLabel.font = YT6.mediumLightFont
        metaLabel.numberOfLines = 1
        likeCountLabel.font = YT6.smallLightFont
        dislikeCountLabel.font = YT6.smallLightFont
        descriptionLabel.font = YT6.mediumLightFont
        titleLabel.isUserInteractionEnabled = true
        titleLabel.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(toggleDescription))
        )
    }

    /// Title (12, 12) 260 wide, its arrow top right, views 2 pt under it,
    /// the separator 12 under those, the description 16 under the likes.
    private func yt6InfoTextConstraints(_ chrome: YT6WatchChrome) -> [NSLayoutConstraint] {
        let cv = contentView
        let pad = YT6.Watch.padding
        let side = YT6.Watch.cardInset
        let card = side + pad
        let arrow = YT6.Watch.arrowSize
        return [
            titleLabel.topAnchor.constraint(equalTo: cv.topAnchor, constant: card),
            titleLabel.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: card),
            titleLabel.trailingAnchor.constraint(
                equalTo: cv.trailingAnchor,
                constant: -card - arrow
            ),
            chrome.disclosure.topAnchor.constraint(equalTo: titleLabel.topAnchor),
            chrome.disclosure.trailingAnchor.constraint(equalTo: metaLabel.trailingAnchor),
            chrome.disclosure.widthAnchor.constraint(equalToConstant: arrow),
            chrome.disclosure.heightAnchor.constraint(equalToConstant: arrow),
            metaLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            metaLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            metaLabel.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -card)
        ] + yt6SeparatorConstraints(chrome)
    }

    private func yt6SeparatorConstraints(_ chrome: YT6WatchChrome) -> [NSLayoutConstraint] {
        let cv = contentView
        let side = YT6.Watch.cardInset
        return [
            chrome.separator.topAnchor.constraint(
                equalTo: metaLabel.bottomAnchor,
                constant: YT6.Watch.padding
            ),
            chrome.separator.leadingAnchor.constraint(
                equalTo: cv.leadingAnchor,
                constant: side + 10
            ),
            chrome.separator.trailingAnchor.constraint(
                equalTo: cv.trailingAnchor,
                constant: -side - 10
            ),
            chrome.separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale)
        ] + [
            descriptionLabel.topAnchor.constraint(
                equalTo: likeButton.bottomAnchor,
                constant: YT6.Watch.infoBottom
            ),
            descriptionLabel.leadingAnchor.constraint(equalTo: chrome.separator.leadingAnchor),
            descriptionLabel.trailingAnchor.constraint(equalTo: metaLabel.trailingAnchor)
        ]
    }

    /// `YTLikesDislikesView layoutSubviews` @6bbb0: like, its count 4 pt
    /// after, dislike 16 pt after that, its count; at the right, where the
    /// flag was, the download button (REQUEST712).
    private func yt6LikesConstraints(_ chrome: YT6WatchChrome) -> [NSLayoutConstraint] {
        [
            likeButton.topAnchor.constraint(
                equalTo: chrome.separator.bottomAnchor,
                constant: YT6.Watch.padding
            ),
            likeButton.leadingAnchor.constraint(equalTo: chrome.separator.leadingAnchor),
            likeCountLabel.leadingAnchor.constraint(
                equalTo: likeButton.trailingAnchor,
                constant: 4
            ),
            dislikeButton.leadingAnchor.constraint(
                equalTo: likeCountLabel.trailingAnchor,
                constant: 16
            ),
            dislikeCountLabel.leadingAnchor.constraint(
                equalTo: dislikeButton.trailingAnchor,
                constant: 4
            ),
            downloadButton.trailingAnchor.constraint(
                equalTo: chrome.separator.trailingAnchor,
                constant: -4
            )
        ] + yt6LikesRowConstraints(chrome)
    }

    /// 21 pt buttons and both counts on the like button's center line.
    private func yt6LikesRowConstraints(_ chrome: YT6WatchChrome) -> [NSLayoutConstraint] {
        let size = YT6.Watch.likeSize
        let center = likeButton.centerYAnchor
        let buttons: [UIButton] = [likeButton, dislikeButton, downloadButton]
        let labels: [UILabel] = [likeCountLabel, dislikeCountLabel]
        return buttons.flatMap {
            [
                $0.widthAnchor.constraint(equalToConstant: size),
                $0.heightAnchor.constraint(equalToConstant: size),
                $0.centerYAnchor.constraint(equalTo: center)
            ]
        } + labels.map { $0.centerYAnchor.constraint(equalTo: center) }
    }

    /// A card plate: the cell's content rect grown by 3 pt each way, `gap`
    /// between this content and the content above.
    private func yt6PlateConstraints(
        _ plate: UIView,
        below anchor: NSLayoutYAxisAnchor,
        gap: CGFloat
    )
        -> [NSLayoutConstraint] {
        let out = YT6.Watch.plateOutset
        let side = YT6.Watch.cardInset
        // The page top has no plate above it: content starts 8 pt down.
        let top = gap == 0 ? side - out : gap - out * 2
        return [
            plate.topAnchor.constraint(equalTo: anchor, constant: top),
            plate.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor,
                constant: side - out
            ),
            plate.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -side + out
            )
        ]
    }

    /// `YTChannelMetadataCell` @3ce080/3ce3a4: 36 pt avatar 12 in, name and
    /// subscribers 10 pt right of it, the 110×30 subscribe switch 12 from
    /// the right, all centered in the 52 pt card.
    private func yt6BuildChannelCard(_ chrome: YT6WatchChrome) {
        yt6Add([
            chrome.channelPlate, channelAvatarView, channelNameLabel, channelMetaLabel,
            subscribeButton
        ], to: contentView)
        channelNameLabel.font = YT6.mediumLightFont
        channelMetaLabel.font = YT6.smallLightFont
        channelMetaLabel.numberOfLines = 1
        // APPROXIMATION: the avatar's `borderStyle 2` frame is not drawn.
        channelAvatarView.layer.cornerRadius = 2
        let button = subscribeButton
        button.layer.cornerRadius = 0
        button.contentEdgeInsets = .zero
        // `YTSubscribeSwitch setSubscribeState:` @40114c: `XSmallLightFont`
        // (11); `layoutSubviews` @400c06/400c2a: the label 5 pt after the
        // icon, the pair centered, the label no wider than the rest.
        button.titleLabel?.font = YT6.xSmallLightFont
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.8
        button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -2.5, bottom: 0, right: 2.5)
        button.titleEdgeInsets = UIEdgeInsets(top: 0, left: 2.5, bottom: 0, right: -2.5)
        let plate = chrome.channelPlate
        let height = YT6.Watch.channelHeight + YT6.Watch.plateOutset * 2
        NSLayoutConstraint.activate(
            yt6PlateConstraints(plate, below: chrome.infoPlate.bottomAnchor, gap: YT6.Watch.cardGap)
                + [plate.heightAnchor.constraint(equalToConstant: height)]
                + yt6ChannelConstraints(plate)
        )
    }

    private func yt6ChannelConstraints(_ plate: UIView) -> [NSLayoutConstraint] {
        let cv = contentView
        let edge = YT6.Watch.cardInset + YT6.Watch.padding
        let avatar = YT6.Watch.avatarSize
        let size = YT6.Watch.subscribeSize
        let button = subscribeButton
        return [
            channelAvatarView.leadingAnchor.constraint(equalTo: cv.leadingAnchor, constant: edge),
            channelAvatarView.centerYAnchor.constraint(equalTo: plate.centerYAnchor),
            channelAvatarView.widthAnchor.constraint(equalToConstant: avatar),
            channelAvatarView.heightAnchor.constraint(equalToConstant: avatar),
            channelNameLabel.leadingAnchor.constraint(
                equalTo: channelAvatarView.trailingAnchor,
                constant: 10
            ),
            channelNameLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: button.leadingAnchor,
                constant: -8
            ),
            channelNameLabel.bottomAnchor.constraint(equalTo: plate.centerYAnchor),
            channelMetaLabel.leadingAnchor.constraint(equalTo: channelNameLabel.leadingAnchor),
            channelMetaLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: button.leadingAnchor,
                constant: -8
            ),
            channelMetaLabel.topAnchor.constraint(equalTo: plate.centerYAnchor, constant: 1),
            button.trailingAnchor.constraint(equalTo: cv.trailingAnchor, constant: -edge),
            button.centerYAnchor.constraint(equalTo: plate.centerYAnchor),
            button.widthAnchor.constraint(equalToConstant: size.width),
            button.heightAnchor.constraint(equalToConstant: size.height)
        ]
    }

    /// Related rows (`YTVideoCell_iPhone`, 95 pt — `YT6VideoRow` draws its
    /// own card plate), «ДРУГИЕ ВАРИАНТЫ» while more are hidden, then the
    /// «КОММЕНТАРИИ · N» header card (`YTCardHeaderCell`, the top of its
    /// section's card) with the comment rows under it.
    private func yt6BuildRelatedAndComments(_ chrome: YT6WatchChrome) {
        yt6StyleButtonCard(chrome.moreCard)
        chrome.moreCard.setTitle(
            YT6.string("video_info.suggestions", fallback: "MORE SUGGESTIONS"),
            for: .normal
        )
        chrome.moreCard.setTitleColor(YT6.Watch.link, for: .normal)
        chrome.moreCard.addTarget(self, action: #selector(yt6ShowMoreRelated), for: .touchUpInside)
        yt6StyleCommentsHeader(chrome)
        yt6Add(
            [relatedCollectionView, chrome.moreCard, chrome.commentsCard, chrome.comments],
            to: contentView
        )
        let more = chrome.moreCard.heightAnchor.constraint(equalToConstant: 0)
        chrome.moreHeight = more
        // Upstream moves the related list into the landscape sidebar and back,
        // re-activating `relatedSlot.portrait` each time: everything that
        // hangs off the list lives in that slot, and the low-priority
        // fallback holds the cards together while the list is away.
        relatedSlot.portrait = yt6RelatedSlot(chrome)
        let fallback = chrome.moreCard.topAnchor.constraint(
            equalTo: chrome.channelPlate.bottomAnchor
        )
        fallback.priority = .defaultLow
        NSLayoutConstraint.activate(
            relatedSlot.portrait + [fallback, more] + yt6CommentsConstraints(chrome)
        )
    }

    /// The header: `grouped_table_card_top` (row 0 of a section of two or
    /// more), the title, the arrow; a tap toggles the rows under it.
    private func yt6StyleCommentsHeader(_ chrome: YT6WatchChrome) {
        yt6StyleButtonCard(chrome.commentsCard)
        chrome.commentsCard.setBackgroundImage(
            YT6.stretchableImage("grouped_table_card_top"),
            for: .normal
        )
        chrome.commentsCard.addTarget(
            self,
            action: #selector(yt6ToggleComments),
            for: .touchUpInside
        )
        chrome.comments.addRow.onTap = { [weak self] in
            self?.yt6AddCommentTapped()
        }
        chrome.commentsTitle.font = YT6.mediumLightFont
        // APPROXIMATION: the header cell sets no color, so the label's black.
        chrome.commentsTitle.textColor = .black
        yt6Add([chrome.commentsTitle, chrome.commentsArrow], to: chrome.commentsCard)
        chrome.commentsTitle.isUserInteractionEnabled = false
        chrome.commentsArrow.isUserInteractionEnabled = false
    }

    private func yt6RelatedSlot(_ chrome: YT6WatchChrome) -> [NSLayoutConstraint] {
        let rv = relatedCollectionView
        let out = YT6.Watch.plateOutset
        let side = YT6.Watch.cardInset
        return [
            rv.topAnchor.constraint(
                equalTo: chrome.channelPlate.bottomAnchor,
                constant: YT6.Watch.cardGap - out * 2
            ),
            rv.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: side - out),
            rv.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor,
                constant: -side + out
            ),
            relatedSlot.height,
            chrome.moreCard.topAnchor.constraint(equalTo: rv.bottomAnchor)
        ].compactMap { $0 }
    }

    private func yt6CommentsConstraints(_ chrome: YT6WatchChrome) -> [NSLayoutConstraint] {
        let cv = contentView
        let out = YT6.Watch.plateOutset
        let side = YT6.Watch.cardInset
        let card = chrome.commentsCard
        let height = YT6.Watch.buttonCardHeight + out * 2
        return [
            chrome.moreCard.leadingAnchor.constraint(
                equalTo: cv.leadingAnchor,
                constant: side - out
            ),
            chrome.moreCard.trailingAnchor.constraint(
                equalTo: cv.trailingAnchor,
                constant: -side + out
            ),
            card.topAnchor.constraint(
                equalTo: chrome.moreCard.bottomAnchor,
                constant: YT6.Watch.cardGap - out * 2
            ),
            card.leadingAnchor.constraint(equalTo: chrome.moreCard.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: chrome.moreCard.trailingAnchor),
            card.heightAnchor.constraint(equalToConstant: height)
        ] + yt6CommentRowsConstraints(chrome) + yt6CommentsHeaderConstraints(chrome)
    }

    /// The rows start where the header's content ends and close the page.
    private func yt6CommentRowsConstraints(_ chrome: YT6WatchChrome) -> [NSLayoutConstraint] {
        let rows = chrome.comments
        let card = chrome.commentsCard
        let height = rows.heightAnchor.constraint(
            equalToConstant: YT6AddCommentRow.height + YT6CommentsView.bottomMargin
        )
        rows.heightConstraint = height
        return [
            rows.topAnchor.constraint(
                equalTo: card.bottomAnchor,
                constant: -YT6.Watch.plateOutset
            ),
            rows.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            rows.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            height
        ]
    }

    /// The header line 12 pt in, its disclosure arrow 12 pt from the right.
    private func yt6CommentsHeaderConstraints(_ chrome: YT6WatchChrome) -> [NSLayoutConstraint] {
        let out = YT6.Watch.plateOutset
        let card = chrome.commentsCard
        let arrow = YT6.Watch.arrowSize
        return [
            chrome.commentsTitle.leadingAnchor.constraint(
                equalTo: card.leadingAnchor,
                constant: out + YT6.Watch.padding
            ),
            chrome.commentsTitle.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chrome.commentsArrow.trailingAnchor.constraint(
                equalTo: card.trailingAnchor,
                constant: -out - YT6.Watch.padding
            ),
            chrome.commentsArrow.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            chrome.commentsArrow.widthAnchor.constraint(equalToConstant: arrow),
            chrome.commentsArrow.heightAnchor.constraint(equalToConstant: arrow)
        ]
    }

    /// `YTCardButtonCell` @3cb70c: a card holding one 13 pt Light line 12 pt
    /// in from the left.
    private func yt6StyleButtonCard(_ button: UIButton) {
        let out = YT6.Watch.plateOutset
        button.setBackgroundImage(YT6.stretchableImage("grouped_table_card"), for: .normal)
        button.titleLabel?.font = YT6.mediumLightFont
        button.contentHorizontalAlignment = .left
        button.contentEdgeInsets = UIEdgeInsets(
            top: 0,
            left: out + YT6.Watch.padding,
            bottom: 0,
            right: YT6.Watch.padding
        )
        button.clipsToBounds = true
    }

    /// `YTVideoActionBarView` along the bottom of the screen: two halves
    /// (add to, share) around a 1×31 separator, `action_bar_shadow` above.
    private func yt6BuildActionBar(_ chrome: YT6WatchChrome) {
        let add = chrome.addToButton, share = chrome.shareButton
        add.setImage(YT6.image("add_to"), for: .normal)
        add.accessibilityLabel = YT6.string("action_bar.add_to.access", fallback: "Add to…")
        add.addTarget(self, action: #selector(saveTapped), for: .touchUpInside)
        share.setImage(YT6.image("action_bar_share"), for: .normal)
        share.accessibilityLabel = YT6.string("action_bar.share.access", fallback: "Share")
        share.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        for button in [add, share] {
            button.showsTouchWhenHighlighted = true
            button.isExclusiveTouch = true
        }
        chrome.actionBar.clipsToBounds = false
        yt6Add([chrome.actionBar], to: view)
        NSLayoutConstraint.activate(yt6ActionBarConstraints(chrome))
        let height = YT6.Watch.actionBarHeight
        scrollView.contentInset.bottom = height
        scrollView.scrollIndicatorInsets.bottom = height
    }

    private func yt6ActionBarConstraints(_ chrome: YT6WatchChrome) -> [NSLayoutConstraint] {
        let bar = chrome.actionBar
        let background = UIImageView(image: YT6.image("action_bar_background"))
        let shadow = UIImageView(image: YT6.stretchableImage("action_bar_shadow"))
        let line = UIView()
        line.backgroundColor = YT6.Watch.actionSeparator
        yt6Add([background, shadow, line, chrome.addToButton, chrome.shareButton], to: bar)
        return [
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: YT6.Watch.actionBarHeight),
            shadow.bottomAnchor.constraint(equalTo: bar.topAnchor),
            shadow.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            shadow.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            shadow.heightAnchor.constraint(equalToConstant: 2),
            line.centerXAnchor.constraint(equalTo: bar.centerXAnchor),
            line.widthAnchor.constraint(equalToConstant: 1),
            line.topAnchor.constraint(equalTo: bar.topAnchor, constant: 10),
            line.bottomAnchor.constraint(equalTo: bar.bottomAnchor, constant: -10)
        ] + yt6Fill(background, in: bar) + yt6HalvesConstraints(chrome)
    }

    private func yt6HalvesConstraints(_ chrome: YT6WatchChrome) -> [NSLayoutConstraint] {
        let bar = chrome.actionBar
        let halves = [chrome.addToButton, chrome.shareButton]
        return [
            chrome.addToButton.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            chrome.addToButton.trailingAnchor.constraint(equalTo: bar.centerXAnchor),
            chrome.shareButton.leadingAnchor.constraint(equalTo: bar.centerXAnchor),
            chrome.shareButton.trailingAnchor.constraint(equalTo: bar.trailingAnchor)
        ] + halves.flatMap {
            [
                $0.topAnchor.constraint(equalTo: bar.topAnchor),
                $0.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
            ]
        }
    }

    private func yt6Fill(_ child: UIView, in parent: UIView) -> [NSLayoutConstraint] {
        [
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ]
    }

    /// `player_details_shadow` (1×2 pt) along the top of the details.
    private func yt6BuildDetailsShadow(_ chrome: YT6WatchChrome) {
        let shadow = chrome.detailsShadow
        shadow.isUserInteractionEnabled = false
        yt6Add([shadow], to: view)
        NSLayoutConstraint.activate([
            shadow.topAnchor.constraint(equalTo: scrollView.topAnchor),
            shadow.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            shadow.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            shadow.heightAnchor.constraint(equalToConstant: 2)
        ])
    }
}

// MARK: - State

extension WatchViewController {
    /// `YTVideoInfoCell` @7a088: `localizedStringFromDate:` with dateStyle
    /// Medium. The watch page's `dateText` is an absolute date on most
    /// videos («3 окт. 2026 г.», «Oct 3, 2026»): read back and printed
    /// Medium. APPROXIMATION: a relative text («2 days ago») has no date to
    /// read and stays as upstream formats it; timeStyle none.
    private static func yt6DescriptionDate(_ text: String) -> String {
        let hasYear = text.range(of: "(19|20)[0-9]{2}", options: .regularExpression) != nil
        let range = NSRange(text.startIndex..., in: text)
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        guard hasYear, let date = detector?.firstMatch(in: text, range: range)?.date else {
            return VideoFormatters.formatRelativeDate(text)
        }
        return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
    }

    /// 2.0.0's fixed colors over whatever upstream's theme just painted.
    func yt6ApplyColors() {
        let surfaces: [UIView] = [view, scrollView, contentView, relatedCollectionView]
        for item in surfaces {
            item.backgroundColor = YT6VideoRow.background
        }
        titleLabel.textColor = YT6.Watch.xDark
        channelNameLabel.textColor = YT6.Watch.xDark
        let grayLabels: [UILabel] = [metaLabel, channelMetaLabel, likeCountLabel, dislikeCountLabel]
        for label in grayLabels {
            label.textColor = YT6.Watch.medium
        }
        yt6UpdateLikes()
        yt6StyleSubscribe()
    }

    /// Each layout pass: what upstream may have reset or changed since.
    func yt6LayoutTick() {
        guard let chrome = yt6 else {
            return
        }
        relatedCollectionView.backgroundColor = YT6VideoRow.background
        let hasMore = visibleRelatedVideos.count < allRelatedVideos.count
        let card = YT6.Watch.buttonCardHeight + YT6.Watch.plateOutset * 2
        let height = hasMore ? card : 0
        if chrome.moreHeight?.constant != height {
            chrome.moreHeight?.constant = height
        }
        chrome.moreCard.isHidden = !hasMore
        let comments = YT6.string("watch.comments", fallback: "COMMENTS")
        let count = watchPage?.commentCount ?? ""
        let title = count.isEmpty ? comments : "\(comments) · \(count)"
        if chrome.commentsTitle.text != title {
            chrome.commentsTitle.text = title
        }
        let isLandscape = view.bounds.width > view.bounds.height
        let gone = chrome.actionBarOffset >= YT6.Watch.actionBarHeight
        chrome.actionBar.isHidden = isLandscape || gone
        yt6SyncComments()
        yt6UpdateDownloadButton()
        view.bringSubviewToFront(chrome.actionBar)
        view.bringSubviewToFront(chrome.videoList)
        view.bringSubviewToFront(chrome.detailsShadow)
        chrome.detailsShadow.isHidden = chrome.videoListExpanded
        if let sheet = sheetView {
            view.bringSubviewToFront(sheet)
        }
    }

    /// The description shows only when the title was tapped
    /// (`YTVideoInfoCell` clips it otherwise); the arrow says which.
    func yt6UpdateDescription() {
        guard let chrome = yt6 else {
            return
        }
        descriptionButton.isHidden = true
        descriptionLabel.isHidden = !descriptionExpanded
        chrome.likesBottom?.isActive = !descriptionExpanded
        chrome.descriptionBottom?.isActive = descriptionExpanded
        chrome.disclosure.image = YT6.image(
            descriptionExpanded
                ? "card_disclosure_arrow_expanded"
                : "card_disclosure_arrow_collapsed"
        )
        chrome.disclosure.isHidden = descriptionText.isEmpty
    }

    /// The description as `YTVideoInfoCell` sets it: «<date> · » in #333,
    /// the text in 13 pt Light #666, links #1B7FCC.
    func yt6ApplyDescriptionText() {
        let body = LinkifiedText.attributedString(
            from: descriptionText,
            font: YT6.mediumLightFont,
            color: YT6.Watch.dark,
            includeTimestamps: true
        )
        let text = NSMutableAttributedString()
        let published = watchPage?.video.publishedAt ?? initialVideo.publishedAt
        if let published, !published.isEmpty {
            text.append(NSAttributedString(
                string: Self.yt6DescriptionDate(published) + " · ",
                attributes: [.font: YT6.mediumLightFont, .foregroundColor: YT6.Watch.xDark]
            ))
        }
        text.append(body)
        descriptionLabel.attributedText = text
        descriptionLabel.linkTextAttributes = [.foregroundColor: YT6.Watch.link]
    }

    /// `like`/`dislike` 21 pt images, `_selected` for the current vote.
    func yt6UpdateLikes() {
        let liked = currentLikeStatus == .like
        let disliked = currentLikeStatus == .dislike
        likeButton.setImage(YT6.image(liked ? "like_selected" : "like"), for: .normal)
        dislikeButton.setImage(YT6.image(disliked ? "dislike_selected" : "dislike"), for: .normal)
        likeCountLabel.textColor = YT6.Watch.medium
        dislikeCountLabel.textColor = YT6.Watch.medium
    }

    /// `YTSubscribeSwitch` @400690: red `button_special` with «ПОДПИСАТЬСЯ»,
    /// light `button_light` with «ВЫ УЖЕ ПОДПИСАНЫ».
    func yt6StyleSubscribe() {
        let button = subscribeButton
        button.backgroundColor = .clear
        let title = isSubscribed
            ? YT6.string("video_info.subscribed", fallback: "SUBSCRIBED")
            : YT6.string("video_info.subscribe", fallback: "SUBSCRIBE")
        button.setTitle(title, for: .normal)
        let plate = isSubscribed ? "button_light" : "button_special"
        button.setBackgroundImage(YT6.stretchableImage(plate), for: .normal)
        button.setImage(YT6.image(isSubscribed ? "subscribed" : "subscribe"), for: .normal)
        // @400e32/400e54: `XLightTextColor` (white) on the red plate,
        // `darkTextColor` (#666) on the light one.
        button.setTitleColor(isSubscribed ? YT6.Watch.dark : .white, for: .normal)
    }

    /// Related cells: 2.0.0 rows, full list width, 95 pt each.
    func yt6RelatedCell(at indexPath: IndexPath) -> UICollectionViewCell {
        let dequeued = relatedCollectionView.dequeueReusableCell(
            withReuseIdentifier: YT6FeedCell.reuseId,
            for: indexPath
        )
        guard let cell = dequeued as? YT6FeedCell else {
            return dequeued
        }
        guard let video = relatedVideo(at: indexPath) else {
            cell.row.configureSkeleton()
            return cell
        }
        cell.row.configure(with: video)
        cell.row.onMenuTap = { [weak self] anchor in
            guard let self else {
                return
            }
            VideoActionMenu.present(video: video, from: self, anchor: anchor)
        }
        return cell
    }

    /// Item size and list height for 95 pt rows with no gaps or header.
    func yt6UpdateRelatedLayout(isLandscape: Bool) {
        let layout = isLandscape ? landscapeRelatedLayout : portraitRelatedLayout
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero
        let width = max(relatedCollectionView.bounds.width, 1)
        let size = CGSize(width: width, height: YT6VideoRow.height)
        if layout.itemSize != size {
            layout.itemSize = size
        }
        let total = CGFloat(visibleRelatedVideos.count) * YT6VideoRow.height
        let desired = (isLandscape && isSheetExpanded) ? 0 : total
        if relatedSlot.height?.constant != desired {
            relatedSlot.height?.constant = desired
        }
        layout.invalidateLayout()
    }

    @objc
    func yt6ShowMoreRelated() {
        expandRelatedIfNeeded()
        updateLayoutForSize()
    }

    /// A new video: the previous one's paused frame and play button stayed
    /// up for the whole load and read as «paused, tap play» (REQUEST698).
    /// The player view is cleared to black with its spinner and no controls.
    /// It exists from the first tap on, so turning the iPod while a fresh
    /// page loads goes to fullscreen, not upstream's landscape page with a
    /// sidebar (REQUEST703: there was no player view to take fullscreen).
    func yt6ShowLoading() {
        let playerView = getOrCreatePlayerView()
        resetPlaybackSurfaces()
        playerView.isHidden = false
        playerView.setControls(visible: false, animated: false)
        playerView.spinner.startAnimating()
        playerContainer.bringSubviewToFront(playerView)
        syncFullscreenWithRotation(isLandscape: view.bounds.width > view.bounds.height)
    }

    /// `YTChannelMetadataCell` @3ce25e: the subscriber count under the
    /// channel name. The watch page does not always carry it, which left
    /// the line empty (REQUEST713); the channel's own info (cached by
    /// `ChannelInfoStore`, the same that brings the avatar) fills it in.
    func yt6FillSubscribers(channelId: String?) {
        let shown = channelMetaLabel.text ?? ""
        guard shown.isEmpty, let channelId, !channelId.isEmpty else {
            return
        }
        let videoId = initialVideo.id
        channelInfoStore.fetch(channelId: channelId) { [weak self] result in
            guard case let .success(info) = result,
                  let count = info.subscriberCountText, !count.isEmpty
            else {
                return
            }
            DispatchQueue.main.async {
                guard let self, self.initialVideo.id == videoId,
                      (self.channelMetaLabel.text ?? "").isEmpty
                else {
                    return
                }
                self.channelMetaLabel.text = count
            }
        }
    }

    /// `overlay_watch_collapse` on the player: back to the collapsed player.
    @objc
    func yt6CollapseTapped() {
        videoRouter.minimize()
    }
}

// MARK: - Action bar riding with the scroll

extension YT6WatchChrome {
    private var barHeight: CGFloat {
        YT6.Watch.actionBarHeight
    }

    /// `scrollViewWillBeginDragging:` @581a4.
    func beginDragging(_ scrollView: UIScrollView) {
        returnTimer?.invalidate()
        dragStartOffset = actionBarOffset
        dragStartY = scrollView.contentOffset.y
    }

    /// `scrollViewDidScroll:` @5823c: the bar travels with the content and
    /// is pinned open at the top, closed at the very end, open when the
    /// content barely scrolls.
    func didScroll(_ scrollView: UIScrollView) {
        guard scrollView.isTracking || scrollView.isDecelerating else {
            return
        }
        let visible = scrollView.bounds.height - barHeight
        if scrollView.contentSize.height <= visible + barHeight * 2 {
            setActionBarOffset(0, animated: true)
            return
        }
        let y = scrollView.contentOffset.y
        if y <= -scrollView.adjustedContentInset.top {
            setActionBarOffset(0, animated: false)
        } else if y >= maxOffsetY(scrollView) {
            setActionBarOffset(barHeight, animated: false)
        } else {
            setActionBarOffset(dragStartOffset + (y - dragStartY), animated: false)
        }
    }

    /// `snapActionBarToState` @5a53c, with the 4 s return.
    func snap(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y
        if y - barHeight <= -scrollView.adjustedContentInset.top {
            setActionBarOffset(0, animated: true)
        } else if y + barHeight >= maxOffsetY(scrollView) {
            setActionBarOffset(barHeight, animated: true)
        } else if actionBarOffset < barHeight / 2 {
            setActionBarOffset(0, animated: true)
        } else {
            setActionBarOffset(barHeight, animated: true)
            returnTimer?.invalidate()
            returnTimer = Timer.scheduledTimer(
                withTimeInterval: YT6.Watch.actionBarReturnDelay,
                repeats: false
            ) { [weak self] _ in
                self?.setActionBarOffset(0, animated: true)
            }
        }
    }

    private func maxOffsetY(_ scrollView: UIScrollView) -> CGFloat {
        let inset = scrollView.adjustedContentInset.bottom
        return scrollView.contentSize.height - scrollView.bounds.height + inset
    }

    /// `setActionBarViewOffset:` @7dd0c: 0 shown … 51 gone below the edge.
    func setActionBarOffset(_ value: CGFloat, animated: Bool) {
        let offset = min(max(value, 0), barHeight)
        guard offset != actionBarOffset else {
            return
        }
        actionBarOffset = offset
        if offset < barHeight {
            actionBar.isHidden = false
        }
        let apply = {
            self.actionBar.transform = CGAffineTransform(translationX: 0, y: offset)
        }
        let finish: (Bool) -> Void = { _ in
            self.actionBar.isHidden = self.actionBarOffset >= self.barHeight
        }
        if animated {
            UIView.animate(
                withDuration: YT6.Watch.actionBarAnimation,
                animations: apply,
                completion: finish
            )
        } else {
            apply()
            finish(true)
        }
    }
}
