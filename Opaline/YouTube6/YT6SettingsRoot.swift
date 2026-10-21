import UIKit

/// The settings screen of the guide, laid out as `YTSettingsViewController`
/// (`viewDidLoad` @4cc90): the account section while signed in
/// (`setTableSectionControllers` @4de5c checks `isAuthenticated`), YOUTUBE,
/// then Opaline's own settings as further sections in the same style, and
/// ABOUT last (`createAboutSection` @4d6b8).
///
/// 2.0.0's YOUTUBE rows (safe search, open links in Chrome, connected TVs)
/// have no Opaline function and are not shown; Opaline's Shorts and PiP are
/// cut (REQUEST680), and appearance and notifications are fixed in the 2013
/// look. See `research/YOUTUBE6-SETTINGS-2026-10-21.md`.
enum YT6SettingsRoot {
    typealias Section = YT6SettingsSection
    typealias Row = YT6SettingsRow

    static func make() -> YT6SettingsViewController {
        YT6SettingsViewController(
            title: YT6.string("settings.title", fallback: "Settings"),
            provider: sections
        )
    }

    /// Any other Opaline page (Debug) drawn the same way, all its rows.
    static func page(_ page: SettingsViewController.Page) -> YT6SettingsViewController {
        YT6SettingsViewController(title: SettingsViewController.title(for: page)) { host in
            host.worker(page).sections.map { section in
                Section(
                    title: section.header?.uppercased(),
                    rows: host.opaline(page, section.rows),
                    note: section.footer
                )
            }
        }
    }

    private static func sections(_ host: YT6SettingsViewController) -> [Section] {
        let account = accountSection(host).map { [$0] } ?? []
        return account + [
            // APPROXIMATION: YOUTUBE holds what Opaline has of YouTube's own
            // service settings — the region (the interface is English, REQUEST719).
            Section(
                title: YT6.string("settings.youtube", fallback: "YOUTUBE"),
                rows: host.opaline(.language, [.region])
            ),
            Section(
                title: YT6SettingsStyle.header("settings.section.playback"),
                rows: host.opaline(.playback, [
                    .quality, .qualityCellular, .backgroundPlayback,
                    .autoZoomToFill, .hideStatusBar,
                    .autoplayEnabled, .autoplayMixEnabled
                ])
            ),
            Section(
                title: YT6SettingsStyle.header("settings.section.autoDub"),
                rows: host.opaline(.playback, [.autoDubEnabled, .autoDubLanguage, .autoDubIgnoreAI])
            ),
            Section(
                title: YT6SettingsStyle.header("settings.section.ryd"),
                rows: host.opaline(.playback, [.rydEnabled]),
                note: "settings.footer.ryd".localized
            ),
            sponsorBlockSection(host),
            YT6SettingsDownloads.section(host),
            cacheSection(host),
            aboutSection(host)
        ]
    }

    /// `YTUserAccountSectionController` (2 rows @174b0, no title): the
    /// account card and the "SIGN OUT" card button in `darkTextColor`
    /// (`cellForRow:` @17570, @175ac). Opaline knows no e-mail address.
    private static func accountSection(_ host: YT6SettingsViewController) -> Section? {
        guard OAuthClient.shared.isSignedIn else {
            return nil
        }
        let profile = UserProfileStore.shared
        var card = Row(title: profile.displayName ?? "account.fallbackName".localized)
        card.kind = .account
        card.image = profile.avatarImage
        var signOut = Row(title: YT6.string("settings.sign_out", fallback: "SIGN OUT")) {
            UIViewController.performSignOut()
        }
        signOut.kind = .button
        signOut.textColor = YT6SettingsStyle.darkText
        return Section(title: nil, rows: [card, signOut])
    }

    private static func sponsorBlockSection(_ host: YT6SettingsViewController) -> Section {
        let row = Row(
            title: "settings.row.sponsorblock".localized,
            detail: YT6SettingsStyle.yesNo(SponsorBlockService.enabled)
        ) { [weak host] in
            host?.navigationController?.pushViewController(
                YT6SponsorBlockSettings.make(), animated: true
            )
        }
        return Section(title: YT6SettingsStyle.header("settings.section.sponsorblock"), rows: [row])
    }

    private static func cacheSection(_ host: YT6SettingsViewController) -> Section {
        Section(
            title: YT6SettingsStyle.header("settings.section.cache"),
            rows: host.opaline(
                .cache, [.persistCache, .feedCacheDays, .imageCacheEnabled, .imageCacheDays]
            )
                + host.opaline(.appearance, [.thumbnailQuality])
                + host.opaline(.cache, [.clearCache])
        )
    }

    /// ABOUT (`createAboutSection` @4d6b8): "Send Feedback" and "Version"
    /// in their 2.0.0 places with Opaline's actions; Help, Terms of Service,
    /// Privacy Policy and Open Source Licences have no Opaline page.
    private static func aboutSection(_ host: YT6SettingsViewController) -> Section {
        let feedback = host.opaline(.root, [.feedback]).map { row in
            var copy = Row(
                title: YT6.string("settings.about.send_feedback", fallback: "Send Feedback")
            )
            copy.select = row.select
            return copy
        }
        let debug = Row(title: "settings.section.debug".localized) { [weak host] in
            host?.navigationController?.pushViewController(page(.debug), animated: true)
        }
        return Section(
            title: YT6.string("settings.about", fallback: "ABOUT"),
            rows: feedback + host.opaline(.root, [.support]) + aboutRows(host) + [debug]
        )
    }

    /// Version, system and model; a tap copies the value, as in Opaline
    /// (`handleAboutSelection`), with the toast on the visible screen.
    private static func aboutRows(_ host: YT6SettingsViewController) -> [Row] {
        let worker = host.worker(.root)
        let rows: [(SettingsViewController.Row, String)] = [
            (.aboutVersion, YT6.string("settings.about.version", fallback: "Version")),
            (.aboutSystem, "settings.about.system".localized),
            (.aboutModel, "settings.about.model".localized)
        ]
        return rows.map { row, title in
            let value = worker.aboutValue(for: row)
            return Row(title: title, detail: value) { [weak host] in
                guard let host else {
                    return
                }
                UIPasteboard.general.string = value
                ToastView.show("common.copied".localized, in: host.view)
            }
        }
    }
}
