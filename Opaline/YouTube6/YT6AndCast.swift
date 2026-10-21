import Foundation
import Security

/// Where videos come from (REQUEST724): YouTube with andCast first for the
/// videos the owner's server already has, the server alone, or only what
/// is saved on the iPod. 2.0.0 had no such choice; APPROXIMATION of a
/// settings value in the 2013 style.
enum YT6Source {
    enum Mode: Int, CaseIterable {
        case youtubeAndCast = 0
        case andCastOnly = 1
        case downloadedOnly = 2

        var title: String {
            switch self {
            case .youtubeAndCast:
                return "YouTube + andCast"
            case .andCastOnly:
                return "andCast only"
            case .downloadedOnly:
                return "Downloaded only"
            }
        }
    }

    static let didChangeNotification = Notification.Name("YT6SourceModeDidChange")
    private static let key = "yt6.source.mode"

    static var mode: Mode {
        get { Mode(rawValue: UserDefaults.standard.integer(forKey: key)) ?? .youtubeAndCast }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: key)
            YT6AndCast.log("mode: \(newValue.title)")
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Nothing may be asked of YouTube in this mode.
    static var isLocal: Bool { mode != .youtubeAndCast }
}

/// andCast: the owner's server — Jellyfin plus the andCast API under
/// `/andcast` — that keeps ~25k of the owner's YouTube videos (REQUEST722,
/// 723). Sign-in, request building and the session are those of the iPod
/// andCast client (`ACClient.m`): `Users/AuthenticateByName` with a
/// `MediaBrowser` identity, the token as `X-Emby-Token`, HTTPS for the
/// server, no redirects followed, no tokens in logs.
enum YT6AndCast {
    struct Session: Codable {
        let server: String
        let userID: String
        let token: String
        let user: String
    }

    static let defaultServer = "https://video.andaleskandsrv.ru"
    static let didChangeNotification = Notification.Name("YT6AndCastDidChange")
    private static let keychainService = "yt6.andcast"
    private static let homeKey = "yt6.andcast.home"
    private static let deviceKey = "yt6.andcast.device"

    private(set) static var session: Session? = loadSession()

    static var isSignedIn: Bool { session != nil }

    /// Optional address of the server inside the home network, tried first.
    static var homeAddress: String? {
        get { UserDefaults.standard.string(forKey: homeKey) }
        set {
            let value = newValue.flatMap { normalized($0, allowHTTP: true) }
            UserDefaults.standard.set(value, forKey: homeKey)
            YT6AndCastReach.refresh()
        }
    }

    /// The device identity the server keys this app's token and copies by;
    /// its own, so signing in here never ends the andCast app's session.
    static var deviceId: String {
        if let saved = UserDefaults.standard.string(forKey: deviceKey) {
            return saved
        }
        let hex = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let made = "youtube6-" + hex.prefix(16).lowercased()
        UserDefaults.standard.set(made, forKey: deviceKey)
        return made
    }

    static func log(_ message: String) {
        AppLog.log("andCast", message)
    }

    /// `+[ACClient normalizedServer:]`: a bare host becomes HTTPS; no
    /// credentials, query or fragment; no trailing slash. The home address
    /// may be plain HTTP (the LAN), the server may not.
    static func normalized(_ input: String, allowHTTP: Bool = false) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard var parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(),
              scheme == "https" || (allowHTTP && scheme == "http"),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil else {
            return nil
        }
        while parts.path.hasSuffix("/") {
            parts.path.removeLast()
        }
        return parts.url?.absoluteString
    }

    // MARK: Sign-in

    static func signIn(
        server: String,
        user: String,
        password: String,
        completion: @escaping (String?) -> Void
    ) {
        let name = user.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let address = normalized(server), let base = URL(string: address), !name.isEmpty
        else {
            completion("Enter an HTTPS server address and a user name.")
            return
        }
        let body: [String: Any] = ["Username": name, "Pw": password]
        guard let request = jellyfin("Users/AuthenticateByName", base: base, body: body) else {
            completion("The server address is not valid.")
            return
        }
        log("sign-in as \(name) at \(base.host ?? "?")")
        perform(request) { result in
            completion(finishSignIn(result, server: address, user: name))
        }
    }

    private static func finishSignIn(
        _ result: Result<Data, Error>,
        server: String,
        user: String
    ) -> String? {
        guard case .success(let data) = result else {
            log("sign-in failed: \(describe(result))")
            return "Sign-in failed. Check the address, user name and password."
        }
        let body = json(data)
        let account = body?["User"] as? [String: Any]
        guard let token = body?["AccessToken"] as? String, !token.isEmpty,
              let userID = account?["Id"] as? String, !userID.isEmpty else {
            return "The server's answer has no session in it."
        }
        let made = Session(server: server, userID: userID, token: token, user: user)
        guard saveSession(made) else {
            return "Could not save the session in the Keychain."
        }
        session = made
        log("signed in as \(user), session in the Keychain")
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
        YT6AndCastReach.refresh()
        return nil
    }

    /// Local sign-out always succeeds; the server is told when it answers.
    static func signOut() {
        if let current = session, let base = URL(string: current.server),
           let request = jellyfin("Sessions/Logout", base: base, body: [String: Any]()) {
            perform(request) { _ in }
        }
        deleteSession()
        session = nil
        YT6AndCastCatalog.shared.reset()
        log("signed out")
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

// MARK: - Keychain

extension YT6AndCast {
    private static var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "session"
        ]
    }

    private static func loadSession() -> Session? {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    private static func saveSession(_ session: Session) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else {
            return false
        }
        deleteSession()
        var add = keychainQuery
        add[kSecValueData as String] = data
        // Readable in a background fetch on a locked iPod, as Opaline's own.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteSession() {
        SecItemDelete(keychainQuery as CFDictionary)
    }
}
