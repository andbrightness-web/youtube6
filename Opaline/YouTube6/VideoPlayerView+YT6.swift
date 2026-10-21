import UIKit

/// The 2.0.0 player bar (`YTPlayerBarView`) built from upstream's own
/// controls, so every action, state update and SponsorBlock segment keeps
/// working: a 44 pt `player_bar_background` along the bottom holding
/// [8 play 8 current-time 8 scrubber 8 duration 8 CC 8 fullscreen 8]
/// (`-[YTPlayerBarView layoutSubviews]` @3b6128, all paddings 8 @3b61fe…),
/// 29 pt buttons, times in `smallLightFont` (12) `XLightTextColor` (white,
/// `initWithMode:` @3b528e). Extras without a 2013 counterpart (PiP, speed,
/// audio only, loop, ±10 s) leave the surface; settings stays as the menu.
extension VideoPlayerView {
    private static let yt6BarHeight: CGFloat = 44
    private static let yt6ButtonSize: CGFloat = 29
    /// Bar buttons answer touches over the bar's full 44 pt (images stay
    /// 29 pt where they were): a near miss hid the controls instead of
    /// pausing (REQUEST702).
    private static let yt6TouchSize: CGFloat = 44
    private static let yt6TouchPad: CGFloat = (yt6TouchSize - yt6ButtonSize) / 2
    private static let yt6Gap: CGFloat = 8
    private static let yt6CollapseTag = 0x7936
    private static let yt6PreviousNextInset: CGFloat = 16

    func yt6RestyleControls() {
        let extras = [pipButton, speedButton, audioOnlyButton, loopButton]
        extras.forEach { $0.isHidden = true }
        topGradientLayer.isHidden = true
        bottomGradientLayer.isHidden = true
        yt6DetachBarViews()
        let bar = UIImageView(image: YT6.stretchableImage("player_bar_background"))
        bar.translatesAutoresizingMaskIntoConstraints = false
        controlsView.insertSubview(bar, at: 0)
        for label in [currentTimeLabel, durationLabel] {
            label.font = YT6.smallLightFont
            label.textColor = .white
        }
        ccButton.setTitle(nil, for: .normal)
        ccButton.setImage(YT6.image("player_bar_cc"), for: .normal)
        ccButton.setImage(YT6.image("player_bar_cc_selected"), for: .selected)
        yt6AddCollapseButton()
        yt6PlaceSettings()
        yt6PlacePreviousNext()
        yt6UpdateIcons()
        yt6ActivateBar(bar)
    }

    /// Upstream's settings stays (quality, captions, speed live there), in
    /// the corner 2.0.0 gives its TV button: top right, 8 pt in, the same
    /// size and line as the collapse button opposite (REQUEST698).
    private func yt6PlaceSettings() {
        let own = settingsButton.constraints.filter { $0.firstItem === settingsButton }
        let placed = controlsView.constraints.filter {
            $0.firstItem === settingsButton
                && ($0.firstAttribute == .top || $0.firstAttribute == .trailing)
        }
        NSLayoutConstraint.deactivate(own + placed)
        let safe = controlsView.safeAreaLayoutGuide
        let inset = YT6.Watch.collapseInset
        NSLayoutConstraint.activate([
            settingsButton.topAnchor.constraint(equalTo: safe.topAnchor, constant: inset),
            settingsButton.trailingAnchor.constraint(
                equalTo: safe.trailingAnchor,
                constant: -inset
            ),
            settingsButton.widthAnchor.constraint(equalToConstant: Self.yt6ButtonSize),
            settingsButton.heightAnchor.constraint(equalToConstant: Self.yt6ButtonSize)
        ])
    }

    /// Upstream's previous/next video buttons hang off the centred play
    /// button, which the bar has taken: 2.0.0 puts them centred vertically,
    /// 16 pt in from each side (`-[YTVideoPlayerOverlayView layoutSubviews]`
    /// @3ba60c/3ba648), at the size of their images.
    private func yt6PlacePreviousNext() {
        let buttons = [rewindButton, forwardButton]
        NSLayoutConstraint.deactivate(buttons.flatMap { button in
            button.constraints.filter { $0.firstItem === button && $0.secondItem == nil }
        })
        let safe = controlsView.safeAreaLayoutGuide
        let inset = Self.yt6PreviousNextInset
        NSLayoutConstraint.activate([
            rewindButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: inset),
            forwardButton.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -inset)
        ] + buttons.map { $0.centerYAnchor.constraint(equalTo: controlsView.centerYAnchor) })
    }

    /// `overlay_watch_collapse` 8 pt in from the top left
    /// (`-[YTPlayerOverlayView layoutSubviews]` @3b85a8), shown with the
    /// controls while the page is expanded. It travels up the responder
    /// chain to the watch page, which owns the panel.
    private func yt6AddCollapseButton() {
        let button = UIButton(type: .custom)
        button.tag = Self.yt6CollapseTag
        button.setImage(YT6.image("overlay_watch_collapse"), for: .normal)
        button.accessibilityLabel = YT6.string("watch.collapse.access", fallback: "Collapse")
        button.addTarget(
            nil,
            action: #selector(WatchViewController.yt6CollapseTapped),
            for: .touchUpInside
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        controlsView.addSubview(button)
        let safe = controlsView.safeAreaLayoutGuide
        let inset = YT6.Watch.collapseInset
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: safe.topAnchor, constant: inset),
            button.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: inset),
            button.widthAnchor.constraint(equalToConstant: Self.yt6ButtonSize),
            button.heightAnchor.constraint(equalToConstant: Self.yt6ButtonSize)
        ])
    }

    /// Drops upstream's placement of the bar views (and only each view's own
    /// size constraints — the seek bar's track is pinned to it by
    /// constraints it also owns).
    private func yt6DetachBarViews() {
        let barViews: [UIView] = [
            playPauseButton, currentTimeLabel, seekBar, durationLabel, ccButton, fullscreenButton
        ]
        let stale = controlsView.constraints.filter { constraint in
            barViews.contains { $0 === constraint.firstItem || $0 === constraint.secondItem }
        }
        let sizes = barViews.flatMap { view in
            view.constraints.filter {
                type(of: $0) == NSLayoutConstraint.self
                    && $0.firstItem === view
                    && $0.secondItem == nil
            }
        }
        NSLayoutConstraint.deactivate(stale + sizes)
    }

    private func yt6ActivateBar(_ bar: UIView) {
        let safe = controlsView.safeAreaLayoutGuide
        let gap = Self.yt6Gap
        let row: [UIView] = [
            playPauseButton, currentTimeLabel, seekBar, durationLabel, ccButton, fullscreenButton
        ]
        var constraints = [
            bar.leadingAnchor.constraint(equalTo: controlsView.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: controlsView.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            bar.heightAnchor.constraint(equalToConstant: Self.yt6BarHeight),
            playPauseButton.leadingAnchor.constraint(
                equalTo: safe.leadingAnchor,
                constant: gap - Self.yt6TouchPad
            ),
            fullscreenButton.trailingAnchor.constraint(
                equalTo: safe.trailingAnchor,
                constant: -gap + Self.yt6TouchPad
            ),
            seekBar.heightAnchor.constraint(equalToConstant: Self.yt6BarHeight)
        ]
        let buttons: [UIView] = [playPauseButton, ccButton, fullscreenButton]
        for (left, right) in zip(row, row.dropFirst()) {
            // Gaps are between the 29 pt images; the frames reach 7.5 pt past them.
            let pads = [left, right].filter { item in buttons.contains { $0 === item } }.count
            let space = gap - CGFloat(pads) * Self.yt6TouchPad
            let link = right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: space)
            constraints.append(link)
        }
        constraints += row.map { $0.centerYAnchor.constraint(equalTo: bar.centerYAnchor) }
        constraints += yt6ButtonSizes()
        NSLayoutConstraint.activate(constraints)
    }

    private func yt6ButtonSizes() -> [NSLayoutConstraint] {
        for label in [currentTimeLabel, durationLabel] {
            label.setContentHuggingPriority(.required, for: .horizontal)
            label.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let size = Self.yt6TouchSize
        return [playPauseButton, ccButton, fullscreenButton].flatMap { button in
            [
                button.widthAnchor.constraint(equalToConstant: size),
                button.heightAnchor.constraint(equalToConstant: size)
            ]
        }
    }
}

extension VideoPlayerView {
    /// `player_bar_play/pause/replay` and `player_bar_fullscreen/smallscreen`
    /// in place of upstream's drawn icons.
    func yt6UpdateIcons() {
        let isPlaying = (player?.rate ?? 0) > 0
        let state = isAtEnd ? "replay" : isPlaying ? "pause" : "play"
        playPauseButton.setImage(YT6.image("player_bar_" + state), for: .normal)
        fullscreenButton.setImage(
            YT6.image(isFullscreen ? "player_bar_smallscreen" : "player_bar_fullscreen"),
            for: .normal
        )
        controlsView.viewWithTag(Self.yt6CollapseTag)?.isHidden = isFullscreen
        yt6UpdatePreviousNext()
    }

    /// `-[YTVideoPlayerOverlayView setVideoButtonsForLayout:]` @3bae84:
    /// `overlay_previous/next[_fullscreen]`, `_disabled` where there is no
    /// video that way — the image says it, not upstream's dimming.
    func yt6UpdatePreviousNext() {
        let suffix = isFullscreen ? "_fullscreen" : ""
        let pairs = [(rewindButton, "overlay_previous"), (forwardButton, "overlay_next")]
        for (button, name) in pairs {
            button.setImage(YT6.image(name + suffix), for: .normal)
            button.setImage(YT6.image(name + suffix + "_disabled"), for: .disabled)
            button.alpha = 1
        }
    }
}
