import Foundation

/// Language rules of youtube6 (REQUEST719, verbatim: «интерфейс ютуба на
/// английском. а названия и дубляжи не то чтобы русские показывать а
/// оригинал, не переводить специально на английский… не завязываться на
/// локали»):
/// - the interface is English whatever the iPod's language
///   (`YT6.interfaceLanguage`; Innertube `hl` the same);
/// - titles are the uploaded ones (`YT6OriginalTitles`);
/// - audio is the original track (`.4`, `acont=original`): auto-dub is off.
///
/// 2.0.0 itself followed the device language; this is the owner's rule, not
/// the donor's.
enum YT6Language {
    private static let appliedKey = "yt6_language_applied"
    private static let contentLanguageKey = "yt6_language_hl"

    /// Called once per launch while the guide is built.
    static func applyDefaults() {
        let defaults = UserDefaults.standard
        // iOS's own texts (system buttons, the share sheet…) follow the app's
        // `AppleLanguages`, from the next launch on.
        let english = [YT6.interfaceLanguage.rawValue]
        if defaults.stringArray(forKey: "AppleLanguages") != english {
            defaults.set(english, forKey: "AppleLanguages")
        }
        // Once: the original audio track, whatever an earlier build or
        // Opaline's default (on) left behind. Settings can still turn it on.
        if !defaults.bool(forKey: appliedKey) {
            defaults.set(false, forKey: UserDefaultsKeys.AutoDub.enabled)
            defaults.set(true, forKey: appliedKey)
        }
        resetCachesIfLanguageChanged(defaults)
        let hl = InnertubeContexts.localePreferences.hl
        let gl = InnertubeContexts.localePreferences.gl
        AppLog.log(
            "Lang",
            "interface=\(YT6.interfaceLanguage.rawValue) hl=\(hl) gl=\(gl)"
                + " autoDub=\(AutoDubPreference.isEnabled)"
                + " device=\(Locale.preferredLanguages.first ?? "-")"
        )
    }

    /// Cached feed pages carry YouTube's texts in the `hl` they were
    /// fetched with («1,2 млн просмотров» from the `hl=ru` builds, which
    /// stored no language — so the first launch of this one resets too) —
    /// the same reset upstream does when its language changes.
    private static func resetCachesIfLanguageChanged(_ defaults: UserDefaults) {
        let current = InnertubeContexts.localePreferences.hl
        let stored = defaults.string(forKey: contentLanguageKey)
        guard stored != current else {
            return
        }
        AppCache.shared.clearAllDiskCache()
        AppLog.log("Lang", "hl \(stored ?? "?") → \(current): feed caches cleared")
        defaults.set(current, forKey: contentLanguageKey)
    }
}
