import UIKit

/// The 2.0.0 value picker (`YTSettingsPickerViewController`).
///
/// `-[YTSettingsViewController showSettingsPickerWithTitle:items:
/// selectedItemIndex:selectBlock:]` @4dcb4 makes one checkmark row per item
/// under a section titled with the setting's uppercase name, the bar titled
/// `settings.title` (`loadView` @4c9ce). `-[YTSettingsViewController_iPhone
/// presentViewController:]` @50888 shows it modally in the styled navigation
/// controller with "Done" on the right (`nav_bar.done` @508b2). A tap applies
/// the value at once and moves the checkmark (`didSelectRow:fromView:`
/// @1569c); the picker stays until Done.
enum YT6SettingsPicker {
    typealias ActionHandler = @convention(block) (UIAlertAction) -> Void

    /// What one picker offers.
    struct Options {
        let title: String
        let items: [String]
        let selected: Int?
        /// APPROXIMATION: text under the rows (no 2.0.0 analog).
        var note: String?
    }

    /// The current choice, shared by the rows of one picker.
    private final class Choice {
        var index: Int?

        init(_ index: Int?) {
            self.index = index
        }
    }

    static func present(
        _ options: Options,
        from host: YT6SettingsViewController,
        onSelect: @escaping (Int) -> Void
    ) {
        let choice = Choice(options.selected)
        let items = options.items
        let note = options.note
        let header = options.title.uppercased(
            with: Locale(identifier: AppLanguage.effective.rawValue)
        )
        let picker = YT6SettingsViewController(
            title: YT6.string("settings.title", fallback: "Settings")
        ) { page in
            let rows = items.enumerated().map { index, item in
                var row = YT6SettingsRow(title: item) { [weak page] in
                    choice.index = index
                    onSelect(index)
                    page?.reload()
                }
                row.checked = choice.index == index
                return row
            }
            return [YT6SettingsSection(title: header, rows: rows, note: note)]
        }
        picker.navigationItem.rightBarButtonItem = doneItem(for: picker)
        let nav = RotatingNavigationController(rootViewController: picker)
        nav.modalPresentationStyle = .fullScreen
        host.presentOnTop(nav)
    }

    /// `+[YTSettingsViewController yesNoItems]` @4ef84: a switch in 2.0.0 is
    /// a "Yes"/"No" value with this two-row picker (`onOpenLinksInChrome`
    /// @4e338).
    static func presentYesNo(
        title: String,
        isOn: Bool,
        from host: YT6SettingsViewController,
        onSelect: @escaping (Bool) -> Void
    ) {
        let options = Options(
            title: title,
            items: [YT6SettingsStyle.yesNo(true), YT6SettingsStyle.yesNo(false)],
            selected: isOn ? 0 : 1
        )
        present(options, from: host) { index in
            onSelect(index == 0)
        }
    }

    /// Shows one of Opaline's choice sheets as this picker: the same items,
    /// the same checkmark, the same handlers. False when the sheet's handlers
    /// cannot be read; the caller then shows the sheet itself.
    static func present(
        sheet: UIAlertController,
        from host: YT6SettingsViewController,
        onChange: @escaping () -> Void
    ) -> Bool {
        let actions = sheet.actions.filter { $0.style != .cancel }
        let handlers = actions.compactMap(handler)
        guard !actions.isEmpty, handlers.count == actions.count else {
            return false
        }
        let options = Options(
            title: sheet.title ?? "",
            items: actions.map { $0.title ?? "" },
            selected: actions.firstIndex(where: isChecked)
        )
        present(options, from: host) { index in
            handlers[index](actions[index])
            onChange()
        }
        return true
    }

    /// `+[UIButton buttonWithStyle:title:]` @3f4b48 with style 2
    /// (`setButtonStyle:` @3f5116): `button_blue`, `button_light` while
    /// pressed, `smallLightFont`, white title (`XLightTextColor`) turning
    /// `lightTextColor` (204) when pressed, 10 pt side insets, the height of
    /// the background image.
    private static func doneItem(for picker: UIViewController) -> UIBarButtonItem {
        let button = UIButton(type: .custom)
        button.setBackgroundImage(YT6.stretchableImage("button_blue"), for: .normal)
        button.setBackgroundImage(YT6.stretchableImage("button_light"), for: .highlighted)
        button.titleLabel?.font = YT6.smallLightFont
        button.setTitle(YT6.string("nav_bar.done", fallback: "Done"), for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.setTitleColor(UIColor(white: 204 / 255, alpha: 1), for: .highlighted)
        button.contentEdgeInsets = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        button.sizeToFit()
        if let height = button.currentBackgroundImage?.size.height {
            button.frame.size.height = height
        }
        button.addTarget(
            picker,
            action: #selector(UIViewController.yt6DismissPicker),
            for: .touchUpInside
        )
        return UIBarButtonItem(customView: button)
    }

    /// `UIAlertAction` keeps its handler and checkmark private; both are
    /// read only when present, so a change in UIKit falls back to the sheet.
    private static func handler(_ action: UIAlertAction) -> ActionHandler? {
        guard action.responds(to: NSSelectorFromString("handler")),
              let block = action.value(forKey: "handler")
        else {
            return nil
        }
        return unsafeBitCast(block as AnyObject, to: ActionHandler.self)
    }

    private static func isChecked(_ action: UIAlertAction) -> Bool {
        // The selectors and ivars key-value coding looks up for "checked".
        let selectors = ["checked", "isChecked", "_checked"]
        let ivars = ["_checked", "_isChecked"]
        let hasMethod = selectors.contains { action.responds(to: NSSelectorFromString($0)) }
        let hasIvar = ivars.contains { name in
            name.withCString { class_getInstanceVariable(UIAlertAction.self, $0) != nil }
        }
        guard hasMethod || hasIvar else {
            return false
        }
        return action.value(forKey: "checked") as? Bool ?? false
    }
}

extension UIViewController {
    @objc
    func yt6DismissPicker() {
        dismiss(animated: true)
    }
}
