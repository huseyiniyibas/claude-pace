import Foundation

public enum LimitsError: Error, Equatable, LocalizedError {
    case credentialsNotFound
    case tokenExpired
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case http(Int)
    case network(String)
    case malformed

    public var errorDescription: String? {
        switch self {
        case .credentialsNotFound:
            "No Claude Code sign-in found. Sign in with `claude` and allow Keychain access."
        case .tokenExpired:
            "Claude Code's sign-in has expired. Use Claude Code once and it refreshes itself."
        case .unauthorized:
            "Anthropic rejected the sign-in (401). Use Claude Code once to refresh it."
        case .rateLimited:
            "The usage endpoint is rate limiting requests, so the numbers may be a few minutes old."
        case .http(let code):
            "Unexpected response from the usage endpoint (HTTP \(code))."
        case .network(let message):
            "Network problem: \(message)"
        case .malformed:
            "The usage endpoint answered in a shape this version does not understand."
        }
    }
}

public struct LimitWindow: Equatable, Codable, Sendable {
    /// Percent of the limit used. 100 means the limit is reached.
    public let utilization: Double
    public let resetsAt: Date?

    public init(utilization: Double, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Equatable, Codable, Sendable {
    public var fiveHour: LimitWindow?
    public var sevenDay: LimitWindow?
    public var sevenDayOpus: LimitWindow?
    public var sevenDaySonnet: LimitWindow?
    public var fetchedAt: Date

    public init(
        fiveHour: LimitWindow? = nil,
        sevenDay: LimitWindow? = nil,
        sevenDayOpus: LimitWindow? = nil,
        sevenDaySonnet: LimitWindow? = nil,
        fetchedAt: Date = Date()
    ) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.sevenDayOpus = sevenDayOpus
        self.sevenDaySonnet = sevenDaySonnet
        self.fetchedAt = fetchedAt
    }

    /// Reads the usage endpoint's JSON. Decoding is deliberately tolerant of
    /// extra and null fields, but a body with neither main window key is
    /// reported as malformed so an API change shows up instead of going blank.
    public static func decode(_ data: Data, fetchedAt: Date = Date()) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root.keys.contains("five_hour") || root.keys.contains("seven_day")
        else { throw LimitsError.malformed }

        func window(_ key: String) -> LimitWindow? {
            guard let body = root[key] as? [String: Any],
                  let utilization = (body["utilization"] as? NSNumber)?.doubleValue
            else { return nil }
            let resetsAt = (body["resets_at"] as? String).flatMap(parseTimestamp)
            return LimitWindow(utilization: utilization, resetsAt: resetsAt)
        }

        return UsageSnapshot(
            fiveHour: window("five_hour"),
            sevenDay: window("seven_day"),
            sevenDayOpus: window("seven_day_opus"),
            sevenDaySonnet: window("seven_day_sonnet"),
            fetchedAt: fetchedAt
        )
    }

    static func parseTimestamp(_ text: String) -> Date? {
        // The endpoint sends microseconds ("...:00.123456+00:00"); sub-second
        // precision is irrelevant here, so drop it before parsing.
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
