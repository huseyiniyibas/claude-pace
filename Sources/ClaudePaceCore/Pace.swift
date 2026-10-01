import Foundation

/// The two rate-limit windows Claude Code enforces.
public enum LimitKind: String, CaseIterable, Codable, Sendable {
    case session
    case weekly

    public var length: TimeInterval {
        switch self {
        case .session: 5 * 3600
        case .weekly: 7 * 24 * 3600
        }
    }

    public var title: String {
        switch self {
        case .session: "Session"
        case .weekly: "Total"
        }
    }
}

public enum PaceVerdict: Equatable, Sendable {
    case warmingUp
    case limitReached
    case slowDown
    case onPace
    case speedUp
    case fullSend

    public var label: String {
        switch self {
        case .warmingUp: "Warming up"
        case .limitReached: "Limit hit"
        case .slowDown: "Slow down"
        case .onPace: "On pace"
        case .speedUp: "Speed up"
        case .fullSend: "Full send"
        }
    }
}

/// Where the verdict bands start, as a projected % of the limit at reset.
public struct PaceThresholds: Equatable, Sendable {
    /// Above this the window will run dry before it resets.
    public var slowDownAbove: Double = 105
    /// From here up to `slowDownAbove` the window ends just about full.
    public var onPaceFrom: Double = 90
    /// From here up to `onPaceFrom` there is room to spare; below it, a lot of room.
    public var speedUpFrom: Double = 65
    /// Share of the window that must pass before a projection is trusted.
    public var warmupFraction: Double = 0.02
    /// A window that is still under this usage counts as warming up.
    public var warmupMaxUsed: Double = 20

    public init() {}
}

public struct PaceEstimate: Equatable, Sendable {
    public let used: Double
    public let remaining: TimeInterval
    public let elapsedFraction: Double
    /// Linear projection of usage at reset, never below what is already used.
    public let projectedAtReset: Double
    /// Time until 100% at the current rate, only when that happens before reset.
    public let timeToLimit: TimeInterval?
    public let verdict: PaceVerdict
}

public enum PaceCalculator {
    /// - Parameters:
    ///   - utilization: percent of the limit used so far.
    ///   - recentRate: percent per second over the recent past, if known. It is
    ///     averaged with the whole-window rate so one idle hour or one burst
    ///     does not swing the verdict.
    public static func estimate(
        utilization used: Double,
        resetsAt: Date,
        windowLength: TimeInterval,
        now: Date,
        recentRate: Double? = nil,
        thresholds: PaceThresholds = PaceThresholds()
    ) -> PaceEstimate {
        let remaining = max(0, resetsAt.timeIntervalSince(now))
        let elapsed = min(max(windowLength - remaining, 0), windowLength)
        let fraction = windowLength > 0 ? elapsed / windowLength : 1

        let averageRate = elapsed > 0 ? used / elapsed : 0
        let rate = recentRate.map { (averageRate + max(0, $0)) / 2 } ?? averageRate
        let projected = max(used, used + rate * remaining)

        var timeToLimit: TimeInterval?
        if used < 100, rate > 0 {
            let seconds = (100 - used) / rate
            if seconds < remaining { timeToLimit = seconds }
        }

        let verdict: PaceVerdict
        if used >= 100 {
            verdict = .limitReached
        } else if fraction < thresholds.warmupFraction, used < thresholds.warmupMaxUsed {
            verdict = .warmingUp
        } else if projected > thresholds.slowDownAbove {
            verdict = .slowDown
        } else if projected >= thresholds.onPaceFrom {
            verdict = .onPace
        } else if projected >= thresholds.speedUpFrom {
            verdict = .speedUp
        } else {
            verdict = .fullSend
        }

        return PaceEstimate(
            used: used,
            remaining: remaining,
            elapsedFraction: fraction,
            projectedAtReset: projected,
            timeToLimit: timeToLimit,
            verdict: verdict
        )
    }
}
