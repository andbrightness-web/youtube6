import UIKit

/// youtube6: Opaline's settings pages, unchanged, behind the 2.0.0 screens.
///
/// A `YT6SettingsViewController` keeps one hidden `SettingsViewController`
/// per page as a child and asks it for each row: the title, the value and
/// the switch come from the very cell Opaline builds, and a tap runs
/// Opaline's own selection handler. Opaline's choice sheets come back here
/// through `present` and are shown as the 2.0.0 picker with the same items
/// and handlers; a switch is shown as a "Yes"/"No" value and the picker
/// flips that same `UISwitch`, firing Opaline's handler.
extension SettingsViewController {
    /// A table the page's handlers can deselect in; its data source is the
    /// page, so the index paths they get are real.
    private var yt6Scratch: UITableView {
        if let table = objc_getAssociatedObject(self, &yt6ScratchKey) as? UITableView {
            return table
        }
        let table = UITableView(frame: .zero, style: .plain)
        table.dataSource = self
        objc_setAssociatedObject(self, &yt6ScratchKey, table, .OBJC_ASSOCIATION_RETAIN)
        return table
    }

    /// Everything the page presents: choice sheets become the 2.0.0 picker,
    /// the rest (alerts, share sheets) goes above the settings screen, which
    /// is on screen while the page itself never is.
    func yt6Present(
        _ controller: UIViewController,
        completion: (() -> Void)?
    ) -> Bool {
        guard let host = parent as? YT6SettingsViewController else {
            return false
        }
        if let sheet = controller as? UIAlertController,
           sheet.preferredStyle == .actionSheet,
           YT6SettingsPicker.present(sheet: sheet, from: host, onChange: { [weak host] in
               host?.reload()
           }) {
            return true
        }
        host.presentOnTop(controller, completion: completion)
        return true
    }

    /// The 2.0.0 row for one of this page's rows, or nil while the page
    /// does not show it.
    func yt6Row(_ row: Row) -> YT6SettingsRow? {
        guard let path = yt6IndexPath(of: row) else {
            return nil
        }
        let cell = tableView(yt6Scratch, cellForRowAt: path)
        let title = cell.textLabel?.text ?? ""
        if let toggle = cell.accessoryView as? UISwitch {
            let value = YT6SettingsStyle.yesNo(toggle.isOn)
            return YT6SettingsRow(title: title, detail: value) { [weak self] in
                self?.yt6PickSwitch(toggle, of: cell, title: title)
            }
        }
        let value = cell.detailTextLabel?.text
        var item = YT6SettingsRow(title: title, detail: value) { [weak self] in
            self?.yt6Select(path)
        }
        // Opaline's destructive cell ("Clear cache") is a centered red line;
        // 2.0.0 puts such an action on a card button.
        if cell.textLabel?.textAlignment == .center {
            item.kind = .button
        }
        return item
    }

    private func yt6IndexPath(of row: Row) -> IndexPath? {
        for (section, item) in sections.enumerated() {
            if let index = item.rows.firstIndex(of: row) {
                return IndexPath(row: index, section: section)
            }
        }
        return nil
    }

    private func yt6Select(_ path: IndexPath) {
        tableView(yt6Scratch, didSelectRowAt: path)
        (parent as? YT6SettingsViewController)?.reload()
    }

    /// The cell stays alive with the picker: it is the switch's target.
    private func yt6PickSwitch(_ toggle: UISwitch, of cell: UITableViewCell, title: String) {
        guard let host = parent as? YT6SettingsViewController else {
            return
        }
        let isOn = toggle.isOn
        YT6SettingsPicker.presentYesNo(title: title, isOn: isOn, from: host) { [weak host] isOn in
            withExtendedLifetime(cell) {
                guard toggle.isOn != isOn else {
                    return
                }
                toggle.setOn(isOn, animated: false)
                toggle.sendActions(for: .valueChanged)
            }
            host?.reload()
        }
    }
}

private var yt6ScratchKey: UInt8 = 0
