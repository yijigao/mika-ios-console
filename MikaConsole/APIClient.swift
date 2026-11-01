import Foundation

/// Never follow redirects with a bearer credential. No request/response logging or disk cache.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
final class APIClient {
    let base: URL
    private let token: String
    private let session: URLSession
    private let delegate: NoRedirectDelegate
    init(base: URL, token: String) {
        self.base = base; self.token = token
        let redirectDelegate = NoRedirectDelegate(); self.delegate = redirectDelegate
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil; config.httpCookieStorage = nil; config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 65; config.timeoutIntervalForResource = 70
        session = URLSession(configuration: config, delegate: redirectDelegate, delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }
    static func normalize(_ input: String) throws -> URL {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") { text = "http://" + text }
        guard var c = URLComponents(string: text), ["http", "https"].contains(c.scheme?.lowercased() ?? ""),
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              c.query == nil, c.fragment == nil, c.path.isEmpty || c.path == "/",
              c.port == nil || (1...65535).contains(c.port!) else { throw ClientError.invalidAddress }
        c.scheme = c.scheme?.lowercased(); c.host = host.lowercased(); c.path = ""
        guard let url = c.url else { throw ClientError.invalidAddress }; return url
    }
    func redact(_ text: String) -> String { text.replacingOccurrences(of: token, with: "[令牌已隐藏]") }
    func request(_ segments: [String] = [], method: String = "GET", body: [String: JSONValue]? = nil,
                 limit: Int? = nil) async throws -> JSONValue {
        var url = base.appendingPathComponent("api").appendingPathComponent("v1")
        if segments.isEmpty { url.appendPathComponent("") }
        for segment in segments {
            // Encode IDs as a single path component, preventing path/query injection.
            guard !segment.isEmpty, segment != ".", segment != "..", !segment.contains("/"), !segment.contains("\\") else {
                throw ClientError.protocolMismatch
            }
            url.appendPathComponent(segment)
        }
        if segments.isEmpty, !url.absoluteString.hasSuffix("/") { url = URL(string: url.absoluteString + "/")! }
        if let limit {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]; url = components.url!
        }
        var r = URLRequest(url: url); r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body { r.httpBody = try JSONEncoder().encode(body); r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await session.data(for: r)
        guard let http = response as? HTTPURLResponse else { throw ClientError.protocolMismatch }
        let json = try? JSONDecoder().decode(JSONValue.self, from: data)
        guard (200...299).contains(http.statusCode) else {
            let error = json?["error"] == .null ? json : json?["error"]
            throw ClientError.http(http.statusCode, redact(error?.text("code") ?? json?.text("code") ?? "http_error"),
                                   redact(error?.text("message") ?? json?.text("message") ?? "服务端未返回结构化错误。"))
        }
        guard let json else { throw ClientError.protocolMismatch }
        return json
    }
    func task(_ id: String) async throws -> RemoteTask { try RemoteTask(try await request(["tasks", id])) }
    func wait(_ id: String) async throws -> RemoteTask {
        try RemoteTask(try await request(["tasks", id, "wait"], method: "POST", body: ["timeout_s": .number(30)]))
    }
    func list() async throws -> [RemoteTask] {
        let json = try await request(["tasks"], limit: 10)
        guard let rows = json.array ?? json["tasks"].array else { throw ClientError.protocolMismatch }
        return try rows.map(RemoteTask.init)
    }
}
