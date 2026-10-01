import Foundation

/// How often to ask the usage endpoint. It rate limits hard (one request a minute
/// was refused after six), and the numbers move slowly, so the default is one check
/// every five minutes, with a longer wait after each refusal.
public struct PollPolicy: Equatable, Sendable {
    public var successInterval: TimeInterval = 300
    /// Network trouble or a server error: try again fairly soon.
    public var transientRetry: TimeInterval = 120
    /// Sign-in problems or an unreadable answer: waiting is the only fix.
    public var persistentRetry: TimeInterval = 300
    public var rateLimitFloor: TimeInterval = 300
    public var rateLimitCeiling: TimeInterval = 1800
    /// No wait is ever longer than this, even if the server asks for more.
    public var longestWait: TimeInterval = 3600
    /// Shortest gap between two refreshes that the user asks for by hand.
    public var manualRefreshGap: TimeInterval = 120

    public init() {}

    /// Seconds to wait before the next request. `rateLimitStreak` counts
    /// consecutive refusals, this one included.
    public func delay(after error: LimitsError, rateLimitStreak: Int) -> TimeInterval {
        switch error {
        case .rateLimited(let retryAfter):
            let doublings = Double(max(0, rateLimitStreak - 1))
            let backoff = min(rateLimitFloor * pow(2, doublings), rateLimitCeiling)
            return min(max(backoff, retryAfter ?? 0), longestWait)
        case .network, .http:
            return transientRetry
        case .credentialsNotFound, .tokenExpired, .unauthorized, .malformed:
            return persistentRetry
        }
    }
}

/// What survives a restart: the last good reading and the polling schedule, so
/// reopening the app neither shows a blank bar nor spends a request.
public struct PollState: Codable, Equatable, Sendable {
    public var snapshot: UsageSnapshot?
    public var lastAttemptAt: Date?
    public var nextAttemptAt: Date?
    public var rateLimitStreak: Int = 0

    public init() {}

    /// A saved reading older than this is not shown after a restart.
    static let snapshotShelfLife: TimeInterval = 30 * 60

    public static var defaultURL: URL {
        JSONFile.supportDirectory.appendingPathComponent("state.json")
    }

    public static func load(from url: URL = defaultURL, now: Date = Date()) -> PollState {
        guard var state = JSONFile.load(PollState.self, from: url) else { return PollState() }
        if let snapshot = state.snapshot, now.timeIntervalSince(snapshot.fetchedAt) > snapshotShelfLife {
            state.snapshot = nil
        }
        return state
    }

    public func save(to url: URL = defaultURL) {
        JSONFile.save(self, to: url)
    }

    /// Manual refresh is closed while the endpoint is refusing requests and for a
    /// short while after any attempt.
    public func canRefreshManually(now: Date, policy: PollPolicy = PollPolicy()) -> Bool {
        guard rateLimitStreak == 0 else { return false }
        guard let lastAttemptAt else { return true }
        return now.timeIntervalSince(lastAttemptAt) >= policy.manualRefreshGap
    }
}
