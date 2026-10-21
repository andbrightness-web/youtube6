import UIKit

/// ANDCAST in the 2013 settings (REQUEST722–724). No 2.0.0 analog: a
/// section in the same style — sign-in to the owner's server (address,
/// user, password → token in the Keychain), the source mode, the home
/// address, which address answers, the catalog on the iPod. The sign-in
/// form is a plain alert with three fields (APPROXIMATION: 2.0.0 signed in
/// through Google's web page, which has no counterpart here).
enum YT6AndCastSettings {
    static func section(_ host: YT6SettingsViewController) -> YT6SettingsSection {
        var rows = accountRows(host)
        rows.append(YT6SettingsRow(title: "Source", detail: YT6Source.mode.title) { [weak host] in
            host.map(pickMode)
        })
        if YT6AndCast.isSignedIn {
            rows += [homeRow(host), connectionRow(host), libraryRow(host)]
        }
        let kept = YT6AndCastStats.shared.pendingCount
        if kept > 0 {
            rows.append(YT6SettingsRow(title: "Kept for YouTube", detail: "\(kept) videos"))
        }
        if YT6AndCast.isSignedIn {
            var signOut = YT6SettingsRow(title: "Sign Out of andCast") { [weak host] in
                YT6AndCast.signOut()
                host?.reload()
            }
            signOut.kind = .button
            signOut.textColor = YT6SettingsStyle.darkText
            rows.append(signOut)
        }
        return YT6SettingsSection(
            title: "ANDCAST",
            rows: rows,
            note: "Videos your server has play from it; YouTube still gets your watch history."
        )
    }

    private static func accountRows(_ host: YT6SettingsViewController) -> [YT6SettingsRow] {
        guard let session = YT6AndCast.session else {
            var signIn = YT6SettingsRow(title: "Sign In to andCast") { [weak host] in
                host.map(askSignIn)
            }
            signIn.kind = .button
            return [signIn]
        }
        let server = URL(string: session.server)?.host ?? session.server
        return [
            YT6SettingsRow(title: "Account", detail: session.user),
            YT6SettingsRow(title: "Server", detail: server)
        ]
    }

    private static func homeRow(_ host: YT6SettingsViewController) -> YT6SettingsRow {
        let current = YT6AndCast.homeAddress.flatMap { URL(string: $0)?.host } ?? "None"
        return YT6SettingsRow(title: "Home Address", detail: current) { [weak host] in
            host.map(askHomeAddress)
        }
    }

    private static func connectionRow(_ host: YT6SettingsViewController) -> YT6SettingsRow {
        let state: String
        if YT6Source.mode == .downloadedOnly {
            state = "Off"
        } else if YT6AndCastReach.isChecking {
            state = "Checking…"
        } else {
            state = YT6AndCastReach.place?.title ?? "Not reachable"
        }
        return YT6SettingsRow(title: "Connection", detail: state) { [weak host] in
            YT6AndCastReach.refresh()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { host?.reload() }
        }
    }

    private static func libraryRow(_ host: YT6SettingsViewController) -> YT6SettingsRow {
        let catalog = YT6AndCastCatalog.shared
        let count = catalog.items.count
        return YT6SettingsRow(title: "Library", detail: syncState(count: count)) { [weak host] in
            catalog.refreshNow()
            host?.reload()
        }
    }

    /// The andCast client's sync words: its phase while it runs, the
    /// server's scan, a failed check, else the count.
    static func syncState(count: Int) -> String {
        let catalog = YT6AndCastCatalog.shared
        if let phase = catalog.phase {
            return phase
        }
        if catalog.serverRefreshing {
            return "Checking for new videos…"
        }
        if catalog.lastError != nil {
            return count > 0 ? "\(count) videos · sync failed" : "Sync failed · tap to retry"
        }
        return count > 0 ? "\(count) videos" : "Not synced"
    }

    // MARK: Actions

    private static func askSignIn(_ host: YT6SettingsViewController) {
        let alert = UIAlertController(
            title: "Sign In to andCast",
            message: "Your andCast (Jellyfin) server, user name and password.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = YT6AndCast.session?.server ?? YT6AndCast.defaultServer
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = "User name"
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addTextField { field in
            field.placeholder = "Password"
            field.isSecureTextEntry = true
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        let action = UIAlertAction(title: "Sign In", style: .default) { [weak host, weak alert] _ in
            let fields = alert?.textFields?.map { $0.text ?? "" } ?? []
            if let host, fields.count == 3 {
                signIn(fields, host: host)
            }
        }
        alert.addAction(action)
        host.presentOnTop(alert)
    }

    private static func signIn(_ fields: [String], host: YT6SettingsViewController) {
        let (server, user, password) = (fields[0], fields[1], fields[2])
        YT6AndCast.signIn(server: server, user: user, password: password) { [weak host] problem in
            guard let host else {
                return
            }
            host.reload()
            if let problem {
                tell(problem, host: host)
            } else {
                ToastView.show("Signed in to andCast", in: host.view)
            }
        }
    }

    private static func askHomeAddress(_ host: YT6SettingsViewController) {
        let alert = UIAlertController(
            title: "Home Address",
            message: "The server's address inside your home network, tried first."
                + " Leave empty for none.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = YT6AndCast.homeAddress
            field.placeholder = "https://192.168.1.10"
            field.keyboardType = .URL
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak host, weak alert] _ in
            let text = alert?.textFields?.first?.text ?? ""
            YT6AndCast.homeAddress = text.isEmpty ? nil : text
            host?.reload()
        })
        host.presentOnTop(alert)
    }

    /// One tap applies the mode, closes the picker and rebuilds the
    /// screens on that mode's data.
    private static func pickMode(_ host: YT6SettingsViewController) {
        let modes = YT6Source.Mode.allCases
        let options = YT6SettingsPicker.Options(
            title: "Source",
            items: modes.map(\.title),
            selected: modes.firstIndex(of: YT6Source.mode),
            note: "andCast only: nothing is asked of YouTube; watched videos are sent to "
                + "your YouTube history later. Downloaded only: no network at all."
        )
        YT6SettingsPicker.present(options, from: host) { [weak host] index in
            let mode = modes[index]
            guard let host, mode != YT6Source.mode else {
                return
            }
            guard mode != .andCastOnly || YT6AndCast.isSignedIn else {
                tell("Sign in to andCast first.", host: host)
                return
            }
            YT6Source.mode = mode
            host.dismiss(animated: true) {
                YT6AndCast.rebuildScreens()
            }
        }
    }

    private static func tell(_ message: String, host: YT6SettingsViewController) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        host.presentOnTop(alert)
    }
}
