import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum ProviderError: Error, LocalizedError, Equatable, Sendable {
    case authentication, forbidden, notFound, rateLimited(Int), server(Int), invalidResponse(String), invalidInput(String)
    public var errorDescription: String? {
        switch self {
        case .authentication: "Authentication expired or invalid. Re-enter this account's credentials in Settings."
        case .forbidden: "Access denied. Check league visibility, account membership, API subscription, and credentials."
        case .notFound: "Not found. Check the league ID and season. Private ESPN leagues may also return 404 without valid cookies."
        case .rateLimited(let seconds): "Provider rate limit reached. Retry after at least \(seconds) seconds."
        case .server(let status): "Provider returned HTTP \(status). Cached scores remain available."
        case .invalidResponse(let message): "Unexpected provider data: \(message)"
        case .invalidInput(let message): message
        }
    }
}

public struct HTTPReply: Sendable {
    public var data: Data
    public var status: Int
    public var retryAfter: Int?
    public init(data: Data, status: Int = 200, retryAfter: Int? = nil) { self.data = data; self.status = status; self.retryAfter = retryAfter }
}
public protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> HTTPReply }

public actor URLSessionTransport: HTTPTransport {
    /// Reuse connections and keep the default URLSession alive for the process.
    /// Credentials are request-scoped; cookie and credential stores are disabled.
    public static let shared = URLSessionTransport()
    private let session: URLSession
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 45
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }
    public func send(_ request: URLRequest) async throws -> HTTPReply {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ProviderError.invalidResponse("Expected HTTP") }
        guard data.count < 64 * 1024 * 1024 else { throw ProviderError.invalidResponse("Response exceeds 64 MB") }
        let header = http.value(forHTTPHeaderField: "Retry-After")
        var retry = header.flatMap(Int.init)
        if retry == nil, let header {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
            retry = formatter.date(from: header).map { max(1, Int($0.timeIntervalSinceNow.rounded(.up))) }
        }
        return .init(data: data, status: http.statusCode, retryAfter: retry)
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        // Authentication cookies and API keys must never follow a redirect to an arbitrary host.
        completionHandler(nil)
    }
}

public actor HTTPClient {
    private let transport: any HTTPTransport
    private var cooldowns: [String: Date] = [:]
    public init(transport: any HTTPTransport = URLSessionTransport.shared) { self.transport = transport }
    public func data(_ request: URLRequest) async throws -> Data {
        let host = request.url?.host ?? ""
        if let until = cooldowns[host], until > .now { throw ProviderError.rateLimited(Int(until.timeIntervalSinceNow.rounded(.up))) }
        for attempt in 0..<3 {
            try Task.checkCancellation()
            let reply: HTTPReply
            do { reply = try await transport.send(request) }
            catch {
                if Task.isCancelled { throw CancellationError() }
                if attempt == 2 { throw error }
                try await Task.sleep(for: .milliseconds(500 * (1 << attempt)))
                continue
            }
            switch reply.status {
            case 200..<300: return reply.data
            case 401: throw ProviderError.authentication
            case 403: throw ProviderError.forbidden
            case 404: throw ProviderError.notFound
            case 429:
                let delay = max(1, reply.retryAfter ?? 60)
                cooldowns[host] = Date.now.addingTimeInterval(Double(delay))
                throw ProviderError.rateLimited(delay)
            case 500...599 where attempt < 2:
                try await Task.sleep(for: .milliseconds(500 * (1 << attempt)))
            default: throw ProviderError.server(reply.status)
            }
        }
        throw ProviderError.invalidResponse("No response")
    }
}

public struct ESPNCredentials: Sendable {
    public var s2: String
    public var swid: String
    public init(s2: String, swid: String) throws {
        guard !s2.isEmpty, !swid.isEmpty, s2.count <= 8192, swid.count <= 256,
              ![s2, swid].contains(where: { $0.contains(where: { $0.isNewline || $0 == ";" || $0.asciiValue == 0 }) }) else {
            throw ProviderError.invalidInput("Enter both ESPN cookies, without newlines or semicolons.")
        }
        self.s2 = s2; self.swid = swid
    }
}

public protocol FantasyProvider: Sendable {
    func load(leagueID: String, season: Int, credentials: ESPNCredentials?, week: Int?) async throws -> LeagueSnapshot
}
public protocol SportsDataProvider: Sendable {
    func games(season: Int, week: Int) async throws -> [NFLGame]
}

public enum RefreshPolicy {
    public static func interval(games: [NFLGame], now: Date = .now, activeInterval: TimeInterval = 60) -> TimeInterval {
        if games.contains(where: \.active) { return max(30, activeInterval) }
        if games.contains(where: { $0.phase == .scheduled && $0.start > now && $0.start.timeIntervalSince(now) < 900 }) { return 120 }
        return 900
    }
    public static func stale(fetchedAt: Date, now: Date = .now, active: Bool) -> Bool { now.timeIntervalSince(fetchedAt) > (active ? 120 : 1800) }
}
