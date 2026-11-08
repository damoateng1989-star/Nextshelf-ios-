import Foundation

/// Errors surfaced to the user in plain language. `detail` is the
/// server's own message (FastAPI `{"detail": ...}`) whenever there is one.
enum APIError: LocalizedError {
    case network(Error)
    case http(status: Int, detail: String?)
    case decoding(Error)
    case notSignedIn
    case unknown

    var errorDescription: String? {
        switch self {
        case .network(let e):
            return e.localizedDescription
        case .http(_, let detail):
            return detail ?? "The server didn't answer properly. Try again."
        case .decoding:
            return "The server sent something unexpected. Try again."
        case .notSignedIn:
            return "Please sign in."
        case .unknown:
            return "The server didn't answer properly. Try again."
        }
    }

    var status: Int? {
        if case .http(let s, _) = self { return s }
        return nil
    }
}

/// The NextShelf API client.
///
/// Auth is a cookie session, exactly like the web app: the server sets
/// `hs_session` (httponly) on login/signup/reset, and this client's
/// URLSession carries it via the shared cookie storage. No token, no
/// Authorization header, no backend change.
///
/// Lineage: the *pattern* (one typed call site, endpoints as an enum)
/// is Regulur's `Router` + `WebService` shape. The code is new:
/// `URLSession` + `Codable` + async/await, cookie auth instead of
/// HTTP Basic Auth, no SVProgressHUD.
final class APIClient {
    static let shared = APIClient()

    static let baseURL = URL(string: "https://nextshelfapp.com")!
    /// The ticker page the v1 chart web view loads.
    static func tickerPageURL(symbol: String) -> URL {
        baseURL.appendingPathComponent("t").appendingPathComponent(symbol.uppercased())
    }
    /// Google sign-in entry point (redirect flow — see GoogleAuthWebView).
    static var googleAuthURL: URL { baseURL.appendingPathComponent("auth/google") }

    /// Webull / Robinhood deep links, same construction as the web app
    /// (`brokerLinks` in static/index.html): Webull needs the exchange
    /// slug, Robinhood takes the bare symbol.
    static func webullURL(symbol: String, exchange: String?) -> URL? {
        guard let exchange, !exchange.isEmpty else { return nil }
        return URL(string: "https://www.webull.com/quote/\(exchange)-\(symbol.lowercased())")
    }

    static func robinhoodURL(symbol: String) -> URL? {
        URL(string: "https://robinhood.com/stocks/\(symbol.uppercased())")
    }

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession? = nil) {
        // The default configuration uses the shared HTTPCookieStorage,
        // which is what carries the session. Stated explicitly so a
        // future refactor doesn't silently break auth.
        var config = URLSessionConfiguration.default
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 30
        // A supplied session (e.g. .shared) already uses the shared
        // cookie storage; otherwise build one from the config above.
        self.session = session ?? URLSession(configuration: config)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder
    }

    // MARK: - Core

    private func request(_ path: String, method: String = "GET",
                         query: [String: String]? = nil, body: Data? = nil) -> URLRequest {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        if let query, !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func perform<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unknown }
        guard (200..<300).contains(http.statusCode) else {
            let detail = try? decoder.decode(ErrorBody.self, from: data).detail?.message
            throw APIError.http(status: http.statusCode, detail: detail)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private func get<T: Decodable>(_ path: String, query: [String: String]? = nil) async throws -> T {
        try await perform(request(path, query: query))
    }

    private func post<T: Decodable, B: Encodable>(_ path: String, body: B) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await perform(request(path, method: "POST", body: data))
    }

    /// POST with no body (e.g. /auth/logout, /api/testcall).
    private func postEmpty<T: Decodable>(_ path: String) async throws -> T {
        try await perform(request(path, method: "POST"))
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        try await perform(request(path, method: "DELETE"))
    }

    // MARK: - Auth

    func authConfig() async throws -> AuthConfig { try await get("auth/config") }

    /// Returns {"ok": true} and sets the session cookie.
    func login(email: String, password: String) async throws -> OkResponse {
        try await post("auth/login", body: LoginRequest(email: email, password: password))
    }

    func signup(email: String, password: String, name: String, invite: String) async throws -> OkResponse {
        try await post("auth/signup", body: SignupRequest(email: email, password: password, name: name, invite: invite))
    }

    func forgot(email: String) async throws -> OkResponse {
        try await post("auth/forgot", body: EmailRequest(email: email))
    }

    func reset(token: String, password: String) async throws -> OkResponse {
        try await post("auth/reset", body: ResetRequest(token: token, password: password))
    }

    func logout() async throws -> OkResponse {
        let out: OkResponse = try await postEmpty("auth/logout")
        // The server also clears the cookie; drop it locally so a stale
        // session can never resurrect.
        if let cookies = HTTPCookieStorage.shared.cookies {
            for c in cookies where c.name == "hs_session" {
                HTTPCookieStorage.shared.deleteCookie(c)
            }
        }
        return out
    }

    // MARK: - Account / settings

    func me() async throws -> MeResponse { try await get("api/me") }

    func setBrief(on: Bool) async throws -> BoolResponse {
        try await post("api/me/brief", body: BoolRequest(on: on))
    }

    func setRecap(on: Bool) async throws -> BoolResponse {
        try await post("api/me/recap", body: BoolRequest(on: on))
    }

    func setCloses(_ closes: String) async throws -> ClosesResponse {
        try await post("api/me/closes", body: ClosesRequest(closes: closes))
    }

    func setQuiet(on: Bool, start: String, end: String) async throws -> QuietResponse {
        try await post("api/me/quiet", body: QuietRequest(on: on, start: start, end: end))
    }

    func setStyles(_ styles: [String]) async throws -> StylesResponse {
        try await post("api/me/styles", body: StylesRequest(styles: styles))
    }

    func setPhone(_ phone: String) async throws -> PhoneResponse {
        try await post("api/me/phone", body: PhoneRequest(phone: phone))
    }

    func unlinkTelegram() async throws -> OkResponse {
        try await delete("api/me/telegram")
    }

    func testCall() async throws -> TestCallResponse {
        try await postEmpty("api/testcall")
    }

    // MARK: - Board / info

    func board() async throws -> BoardResponse { try await get("api/board") }
    func info() async throws -> InfoResponse { try await get("api/info") }
    func publicSummary() async throws -> PublicSummary { try await get("api/public/summary") }

    // MARK: - Shelf card

    func chart(symbol: String, tf: String = "4h") async throws -> ChartResponse {
        try await get("api/chart/\(symbol.uppercased())", query: ["tf": tf])
    }

    /// 403 when the server's options gate is off for this member.
    func options(symbol: String) async throws -> OptionsPlanResponse {
        try await get("api/options/\(symbol.uppercased())")
    }

    /// Fail-open on the server: `walls` is null when there is no chain.
    func gamma(symbol: String) async throws -> GammaResponse {
        try await get("api/gamma/\(symbol.uppercased())")
    }

    func earnings(symbols: [String]) async throws -> [String: EarningsEntry] {
        try await get("api/earnings", query: ["symbols": symbols.joined(separator: ",")])
    }

    // MARK: - Watchlist

    func tickers() async throws -> [WatchlistItem] { try await get("api/tickers") }

    /// 402 when the Free tier cap is hit.
    func addTicker(_ symbol: String) async throws -> AddTickerResponse {
        try await post("api/tickers", body: AddTickerRequest(symbol: symbol.uppercased()))
    }

    func removeTicker(_ symbol: String) async throws -> OkResponse {
        try await delete("api/tickers/\(symbol.uppercased())")
    }

    // MARK: - Record / paper

    func record(pattern: String) async throws -> RecordResponse {
        try await get("api/record", query: ["pattern": pattern])
    }

    /// Admin only on the server — callers must check `me.isAdmin` first.
    func paper() async throws -> PaperSummary { try await get("api/paper") }

    // MARK: - Tiny response shapes

    struct OkResponse: Decodable { var ok: Bool? }
    struct BoolResponse: Decodable { var brief: Bool?; var recap: Bool? }
    struct ClosesResponse: Decodable { var closes: String? }
    struct QuietResponse: Decodable { var quiet: String? }
    struct StylesResponse: Decodable { var styles: [String]? }
    struct PhoneResponse: Decodable { var phone: String? }
    struct TestCallResponse: Decodable { var sid: String? }
}

// MARK: - Server date parsing
//
// The server sends ISO timestamps in two shapes: pandas ISO
// ("2026-11-07T13:52:00-05:00") and DB strings ("2026-11-07 13:52:00").
// Try ISO8601 first, then the DB shape. All times are New York time.

enum ServerDate {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let dbFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f
    }()

    private static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f
    }()

    static func parse(_ string: String?) -> Date? {
        guard let string, !string.isEmpty else { return nil }
        if let d = isoWithFractional.date(from: string) { return d }
        if let d = iso.date(from: string) { return d }
        if let d = dbFormat.date(from: string) { return d }
        if let d = dateOnly.date(from: string) { return d }
        return nil
    }

    /// "Updated 1:32 PM ET" style, New York time.
    static func updatedLine(_ string: String?) -> String? {
        guard let date = parse(string) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        f.timeZone = TimeZone(identifier: "America/New_York")
        return "Updated \(f.string(from: date)) ET"
    }

    static func shortDate(_ string: String?) -> String? {
        guard let date = parse(string) else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.timeZone = TimeZone(identifier: "America/New_York")
        return f.string(from: date)
    }
}
