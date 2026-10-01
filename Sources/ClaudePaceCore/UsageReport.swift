import Foundation

public struct WindowReport: Equatable, Sendable {
    public let kind: LimitKind
    public let window: LimitWindow
    /// Nil when the endpoint gave no reset time, so no projection is possible.
    public let estimate: PaceEstimate?

    public var percentText: String { "\(Int(window.utilization.rounded()))%" }

    /// One bar segment, for example `Session 77% - 3h 49m left | Slow down`,
    /// built from whichever details are switched on for this window.
    public func segment(options: WindowOptions = WindowOptions()) -> BarSegment {
        var stats: [String] = []
        if options.fields.contains(.percent) { stats.append(percentText) }
        if options.fields.contains(.timeLeft), let estimate {
            stats.append("\(DurationFormat.left(estimate.remaining)) left")
        }
        if options.fields.contains(.limitIn), let timeToLimit = estimate?.timeToLimit {
            stats.append("limit in \(DurationFormat.left(timeToLimit))")
        }
        let verdict = options.fields.contains(.keyword) ? estimate?.verdict : nil
        // The chosen details may have nothing to show for this window (no reset
        // time was reported); fall back to the percentage rather than a bare label.
        if stats.isEmpty, verdict == nil { stats.append(percentText) }

        var pieces: [String] = []
        if options.showsLabel { pieces.append(kind.title) }
        if !stats.isEmpty { pieces.append(stats.joined(separator: " - ")) }
        return BarSegment(text: pieces.joined(separator: " "), verdict: verdict)
    }
}

public struct BarSegment: Equatable, Sendable {
    /// Everything but the keyword. Empty when only the keyword is shown.
    public let text: String
    public let verdict: PaceVerdict?

    /// Goes between `text` and the keyword; nothing when there is no text to divide from.
    public var verdictSeparator: String { text.isEmpty ? "" : " | " }

    public var plain: String {
        guard let verdict else { return text }
        return text + verdictSeparator + verdict.label
    }
}

public struct UsageReport: Equatable, Sendable {
    public let session: WindowReport?
    public let weekly: WindowReport?
    public let sonnet: LimitWindow?
    public let opus: LimitWindow?

    public static let segmentSeparator = "   "

    public init(
        snapshot: UsageSnapshot,
        history: SampleHistory,
        now: Date,
        thresholds: PaceThresholds = PaceThresholds()
    ) {
        func report(_ kind: LimitKind, _ window: LimitWindow?) -> WindowReport? {
            guard let window else { return nil }
            guard let resetsAt = window.resetsAt else {
                return WindowReport(kind: kind, window: window, estimate: nil)
            }
            let rate = history.recentRate(kind, windowStart: resetsAt.addingTimeInterval(-kind.length), now: now)
            let estimate = PaceCalculator.estimate(
                utilization: window.utilization,
                resetsAt: resetsAt,
                windowLength: kind.length,
                now: now,
                recentRate: rate,
                thresholds: thresholds
            )
            return WindowReport(kind: kind, window: window, estimate: estimate)
        }
        session = report(.session, snapshot.fiveHour)
        weekly = report(.weekly, snapshot.sevenDay)
        sonnet = snapshot.sevenDaySonnet
        opus = snapshot.sevenDayOpus
    }

    /// The segments to draw, each built from its own window's options. If none of
    /// the windows meant to be shown is in the data, every available window is
    /// shown instead of leaving the bar empty.
    public func segments(options: BarOptions = .default) -> [BarSegment] {
        let available = [session, weekly].compactMap { $0 }
        let chosen = available.filter { options[$0.kind].isShown }
        return (chosen.isEmpty ? available : chosen).map { $0.segment(options: options[$0.kind]) }
    }

    public func barText(options: BarOptions = .default) -> String {
        segments(options: options).map(\.plain).joined(separator: Self.segmentSeparator)
    }
}
