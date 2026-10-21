import UIKit

/// SponsorBlock as its own page in the 2013 settings style (no 2.0.0
/// analog): Opaline's on/off switch as a "Yes"/"No" row, then — while on —
/// one row per `SBCategory` with its current action on the right and the
/// color `VideoSeekBar` paints its segments in as a square on the left
/// (`SBCategory.seekBarColor`, as `refreshSponsorSeekBar` uses it). A tap
/// picks the action from `SBSkipBehavior.options(for:)` and stores it with
/// `SponsorBlockService.setSkipBehavior`, exactly as Opaline's page does.
enum YT6SponsorBlockSettings {
    static func make() -> YT6SettingsViewController {
        YT6SettingsViewController(
            title: "settings.section.sponsorblock".localized,
            provider: sections
        )
    }

    private static func sections(_ host: YT6SettingsViewController) -> [YT6SettingsSection] {
        var list = [
            YT6SettingsSection(
                title: YT6SettingsStyle.header("settings.section.sponsorblock"),
                rows: host.opaline(.sponsorBlock, [.sponsorBlockEnabled])
            )
        ]
        if SponsorBlockService.enabled {
            list.append(
                YT6SettingsSection(
                    title: YT6SettingsStyle.header("sponsorblock.segmentCategories"),
                    rows: SBCategory.allCases.map { row($0, host: host) },
                    note: SponsorBlockService.attributionText
                )
            )
        }
        return list
    }

    private static func row(
        _ category: SBCategory,
        host: YT6SettingsViewController
    ) -> YT6SettingsRow {
        var row = YT6SettingsRow(
            title: category.displayName,
            detail: SponsorBlockService.skipBehavior(for: category).displayName
        ) { [weak host] in
            host.map { pickBehavior(for: category, from: $0) }
        }
        row.swatch = category.seekBarColor
        return row
    }

    private static func pickBehavior(
        for category: SBCategory,
        from host: YT6SettingsViewController
    ) {
        let options = SBSkipBehavior.options(for: category)
        let current = SponsorBlockService.skipBehavior(for: category)
        let picker = YT6SettingsPicker.Options(
            title: category.displayName,
            items: options.map(\.displayName),
            selected: options.firstIndex(of: current),
            note: category.categoryDescription
        )
        YT6SettingsPicker.present(picker, from: host) { [weak host] index in
            SponsorBlockService.setSkipBehavior(options[index], for: category)
            host?.reload()
        }
    }
}
