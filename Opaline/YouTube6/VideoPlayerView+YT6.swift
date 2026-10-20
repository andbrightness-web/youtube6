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
    private static let yt6Gap: CGFloat = 8

    func yt6RestyleControls() {
        let extras = [
            pipButton, speedButton, audioOnlyButton, loopButton, rewindButton, forwardButton
        ]
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
        yt6UpdateIcons()
        yt6ActivateBar(bar)
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
            playPauseButton.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: gap),
            fullscreenButton.trailingAnchor.constraint(
                equalTo: safe.trailingAnchor,
                constant: -gap
            ),
            seekBar.heightAnchor.constraint(equalToConstant: Self.yt6BarHeight)
        ]
        for (left, right) in zip(row, row.dropFirst()) {
            let link = right.leadingAnchor.constraint(equalTo: left.trailingAnchor, constant: gap)
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
        let size = Self.yt6ButtonSize
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
    }
}
