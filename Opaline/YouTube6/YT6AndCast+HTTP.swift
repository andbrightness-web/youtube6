import Foundation

/// Refuses every redirect, as `ACClient` does: a token must never follow
/// a `Location` to some other host.
private final class YT6NoRedirects: NSObject, URLSessionTaskDelegate {
    // swiftlint:disable:next function_parameter_count
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum YT6AndCastError: LocalizedError {
    case unavailable(String)
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .unavailable(let why):
            return why
        case .http(let code):
            return "andCast answered HTTP \(code)"
        }
    }
}

/// Requests to andCast: the andCast client's `requestAt:path:query:token:`
/// (identity header, JSON, `X-Emby-Token`) on its own ephemeral session.
extension YT6AndCast {
    private static let delegate = YT6NoRedirects()

    static let urlSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 180
        config.httpShouldSetCookies = false
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()

    /// `MediaBrowser Client=…, Device=…, DeviceId=…, Version=…`.
    static var identity: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "1"
        return "MediaBrowser Client=\"youtube6\", Device=\"iPod\", "
            + "DeviceId=\"\(deviceId)\", Version=\"\(version)\""
    }

    /// A Jellyfin path under `base`; POST with a JSON body when one is given.
    static func jellyfin(
        _ path: String,
        base: URL,
        query: [String: String] = [:],
        body: Any? = nil
    ) -> URLRequest? {
        let url = base.appendingPathComponent(path)
        var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            parts?.queryItems = query.sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = parts?.url else {
            return nil
        }
        var request = URLRequest(url: url)
        request.setValue(identity, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = session?.token {
            request.setValue(token, forHTTPHeaderField: "X-Emby-Token")
        }
        if let body, let data = try? JSONSerialization.data(withJSONObject: body) {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = data
        }
        return request
    }

    /// An andCast API path: `<server>/andcast/<path>`
    /// (`serviceRequest:query:body:`).
    static func api(
        _ path: String,
        base: URL,
        query: [String: String] = [:],
        body: Any? = nil
    ) -> URLRequest? {
        jellyfin("andcast/" + path, base: base, query: query, body: body)
    }

    /// Runs a request; 2xx bodies succeed, anything else is an error.
    static func perform(
        _ request: URLRequest,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        urlSession.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let result: Result<Data, Error>
            if let error {
                result = .failure(error)
            } else if (200..<300).contains(status) {
                result = .success(data ?? Data())
            } else {
                result = .failure(YT6AndCastError.http(status))
            }
            DispatchQueue.main.async { completion(result) }
        }
        .resume()
    }

    /// GET/POST against the reachable address, JSON object back.
    static func call(
        _ path: String,
        query: [String: String] = [:],
        body: Any? = nil,
        completion: @escaping ([String: Any]?) -> Void
    ) {
        YT6AndCastReach.current { base in
            guard let base, let request = api(path, base: base, query: query, body: body) else {
                completion(nil)
                return
            }
            perform(request) { result in
                if case .failure = result {
                    log("\(path): \(describe(result))")
                }
                completion((try? result.get()).flatMap(json))
            }
        }
    }

    static func json(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// An error for the log: the code, never the URL (it may hold a token).
    static func describe<T>(_ result: Result<T, Error>) -> String {
        guard case .failure(let error) = result else {
            return "ok"
        }
        if let own = error as? YT6AndCastError {
            return own.errorDescription ?? "error"
        }
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code)"
    }

    /// Artwork of an item or a channel, under the server's canonical
    /// address; the transport moves it to the reachable one and signs it.
    static func artworkURL(_ item: String, revision: String?) -> String? {
        guard let revision, !revision.isEmpty, let server = session?.server else {
            return nil
        }
        return server + "/andcast/v1/artwork/\(item)/\(revision)"
    }

    /// Hosts that are andCast: the server and the home address.
    static func isOwnHost(_ host: String) -> Bool {
        let own = [session?.server, homeAddress]
            .compactMap { $0.flatMap(URL.init(string:))?.host?.lowercased() }
        return own.contains(host.lowercased())
    }
}
