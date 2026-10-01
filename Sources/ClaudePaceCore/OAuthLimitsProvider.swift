import Foundation

public protocol LimitsProvider: Sendable {
    func fetch() async throws -> UsageSnapshot
}

public struct OAuthCredentials: Sendable {
    let accessToken: String
    let expiresAt: Date?
}

public enum CredentialParser {
    /// Pulls the access token and its expiry out of Claude Code's stored
    /// sign-in JSON. The refresh token is never read: refreshing here could
    /// rotate it and sign Claude Code itself out.
    static func parse(_ data: Data) throws -> OAuthCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty
        else { throw LimitsError.credentialsNotFound }

        var expiresAt: Date?
        if let raw = (oauth["expiresAt"] as? NSNumber)?.doubleValue {
            expiresAt = Date(timeIntervalSince1970: raw > 1e12 ? raw / 1000 : raw)
        }
        return OAuthCredentials(accessToken: token, expiresAt: expiresAt)
    }
}

public protocol CredentialSource: Sendable {
    func load() async throws -> OAuthCredentials
}

/// Reads the sign-in Claude Code keeps in the macOS Keychain, through the
/// system `security` tool so a Keychain "Always Allow" survives rebuilds.
public struct KeychainCredentialSource: CredentialSource {
    public init() {}

    public func load() async throws -> OAuthCredentials {
        let data = try await Self.runSecurity()
        return try CredentialParser.parse(data)
    }

    private static func runSecurity() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
                process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
                let output = Pipe()
                process.standardOutput = output
                process.standardError = Pipe()
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: LimitsError.credentialsNotFound)
                    return
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                if process.terminationStatus == 0, !data.isEmpty {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: LimitsError.credentialsNotFound)
                }
            }
        }
    }
}

/// Fallback for setups where Claude Code stores its sign-in in a file.
public struct FileCredentialSource: CredentialSource {
    let url: URL

    public init(url: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/.credentials.json")) {
        self.url = url
    }

    public func load() async throws -> OAuthCredentials {
        guard let data = try? Data(contentsOf: url) else { throw LimitsError.credentialsNotFound }
        return try CredentialParser.parse(data)
    }
}

/// Asks the same unofficial endpoint Claude Code's own usage screen uses for the
/// real session and weekly percentages and their reset times.
public struct OAuthLimitsProvider: LimitsProvider {
    private let sources: [any CredentialSource]
    private let session: URLSession
    private let endpoint: URL

    public init(
        sources: [any CredentialSource] = [KeychainCredentialSource(), FileCredentialSource()],
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    ) {
        self.sources = sources
        self.session = session
        self.endpoint = endpoint
    }

    public func fetch() async throws -> UsageSnapshot {
        try UsageSnapshot.decode(try await fetchRaw())
    }

    /// The endpoint's response body, which holds usage numbers only.
    public func fetchRaw() async throws -> Data {
        let credentials = try await firstCredentials()
        if let expiresAt = credentials.expiresAt, expiresAt <= Date() {
            throw LimitsError.tokenExpired
        }

        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-pace/0.1", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LimitsError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw LimitsError.malformed }
        switch http.statusCode {
        case 200: return data
        case 401, 403: throw LimitsError.unauthorized
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw LimitsError.rateLimited(retryAfter: retry)
        default: throw LimitsError.http(http.statusCode)
        }
    }

    private func firstCredentials() async throws -> OAuthCredentials {
        for source in sources {
            do {
                return try await source.load()
            } catch LimitsError.credentialsNotFound {
                continue
            }
        }
        throw LimitsError.credentialsNotFound
    }
}

/// Fixed numbers for trying the menu bar without any sign-in. Used by `--demo`.
public struct DemoLimitsProvider: LimitsProvider {
    public init() {}

    public func fetch() async throws -> UsageSnapshot {
        let now = Date()
        // Half a minute over, so a countdown still reads "3h 49m" for the first
        // thirty seconds instead of dropping to "3h 48m" the moment it is shown.
        return UsageSnapshot(
            fiveHour: LimitWindow(utilization: 77, resetsAt: now.addingTimeInterval(3 * 3600 + 49 * 60 + 30)),
            sevenDay: LimitWindow(utilization: 67, resetsAt: now.addingTimeInterval(25 * 3600 + 51 * 60 + 30)),
            fetchedAt: now
        )
    }
}
