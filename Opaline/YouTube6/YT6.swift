import UIKit

/// youtube6: Opaline dressed as the YouTube 2.0.0 iPhone app (iOS 6 era).
///
/// Metrics, colors and fonts are read from the 2.0.0 binary (armv7, not
/// encrypted); the address next to each value is where it lives there.
/// Artwork is Google's and is never committed: `scripts/yt6-fetch-donor.sh`
/// copies it into `Opaline/YouTube6/Donor` at build time as `yt6_<name>.png`.
enum YT6 {
    /// The fork always runs in the 2013 look; kept as a switch so every hook
    /// into upstream code reads the same way.
    static let isEnabled = true

    /// Content language (`hl`) for Innertube: Russian, so Russian videos
    /// keep their own titles instead of YouTube's English auto-translations
    /// on an English-language iPod (REQUEST688). The 2.0.0 interface still
    /// follows the device language.
    static var contentLanguage: String? {
        isEnabled ? AppLanguage.russian.rawValue : nil
    }

    // MARK: Guide

    /// `+[YTBaseGuideCell cellWidth]` @5c612.
    static let guideWidth: CGFloat = 272
    /// `+[YTBaseGuideCell cellHeightForEntry:width:]` @5c60a.
    static let guideRowHeight: CGFloat = 49
    /// `+[YTGuideSectionHeader preferredHeight]` @6686e.
    static let guideHeaderHeight: CGFloat = 22
    /// `-[YTBaseGuideCell layoutSubviews]`: thumbnail top-left (7, 10) @5beec,
    /// title 10 pt right of it @5bf64; `initWithReuseIdentifier:` thumbnail
    /// mask 35 pt @5bc0a, title width 168 @5bd0e.
    static let guideIconOrigin = CGPoint(x: 7, y: 10)
    static let guideIconSize: CGFloat = 35
    static let guideTitleGap: CGFloat = 10
    static let guideTitleWidth: CGFloat = 168
    /// `-[YTGuideSectionHeader layoutSubviews]` label padding @66858.
    static let guideHeaderPadding: CGFloat = 10
    /// `-[YTGuideContainerView bounceWithOffset:]` @65fde.
    static let guideBounce: CGFloat = 32
    /// APPROXIMATION: the slide duration is a double constant not yet read
    /// from `maximize`/`minimize`.
    static let guideSlideDuration: TimeInterval = 0.25

    // MARK: Colors (UIColor(YTColors))

    /// `+backgroundDarkColor` @3f555c — guide table background.
    static let guideBackground = gray(39)
    /// `+cellGuideTitleColor` @3f569c.
    static let guideTitle = gray(153)
    /// `+cellGuideSelectedTitleColor` @3f5680 — `whiteColor`.
    static let guideTitleSelected = UIColor.white
    /// `+cellGuideUnreadCountColor` @3f56cc.
    static let guideUnreadCount = gray(204)
    /// `+cellGuideSectionHeaderColor` @3f5654.
    static let guideSectionHeader = gray(136)
    /// `+titleBarTextColor` @3f5a2a.
    static let titleBarText = gray(34)

    // MARK: Fonts (UIFont(YTFonts) fontWithName:iPadSize:iPhoneSize:)

    /// `+XLargeLightFont` @3f5f1c — HelveticaNeue-Light 16 (guide titles,
    /// navigation bar title).
    static let xLargeLightFont = font(16)
    /// `+smallLightFont` @3f5e98 — 12.
    static let smallLightFont = font(12)
    /// `+XXSmallLightFont` @3f5e44 — 10 (guide section headers).
    static let xxSmallLightFont = font(10)
    /// `+mediumLightFont` — 13 (watch page text, `YTVideoInfoCell`).
    static let mediumLightFont = font(13)
    /// `+XSmallLightFont` — 11.
    static let xSmallLightFont = font(11)

    // MARK: Strings

    private static let strings: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "yt6_strings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let table = object as? [String: [String: String]]
        else {
            return [:]
        }
        return table
    }()

    private static func gray(_ value: CGFloat) -> UIColor {
        UIColor(red: value / 255, green: value / 255, blue: value / 255, alpha: 1)
    }

    private static func font(_ size: CGFloat) -> UIFont {
        UIFont(name: "HelveticaNeue-Light", size: size)
            ?? .systemFont(ofSize: size, weight: .light)
    }

    // MARK: Artwork

    /// A donor image as shipped (`yt6_<name>.png`), drawn as is.
    static func image(_ name: String) -> UIImage? {
        UIImage(named: "yt6_" + name)?.withRenderingMode(.alwaysOriginal)
    }

    /// `+[YTResources imageNamed:stretchable:selected:]` @7006: stretchable
    /// images get caps at half their width and height
    /// (`stretchableImageWithLeftCapWidth:topCapHeight:`), i.e. a one-point
    /// middle that stretches.
    static func stretchableImage(_ name: String) -> UIImage? {
        guard let image = image(name) else {
            return nil
        }
        let left = (image.size.width / 2).rounded(.down)
        let top = (image.size.height / 2).rounded(.down)
        let insets = UIEdgeInsets(
            top: top,
            left: left,
            bottom: max(image.size.height - top - 1, 0),
            right: max(image.size.width - left - 1, 0)
        )
        return image.resizableImage(withCapInsets: insets, resizingMode: .stretch)
    }

    /// A 2.0.0 `Localizable.strings` entry in the user's language, falling
    /// back to English and then to `fallback`.
    static func string(_ key: String, fallback: String) -> String {
        let languages = Locale.preferredLanguages.map {
            String($0.split(separator: "-").first ?? Substring($0))
        }
        for language in languages + ["en", "English"] {
            if let value = strings[language]?[key] {
                return value
            }
        }
        return fallback
    }
}
