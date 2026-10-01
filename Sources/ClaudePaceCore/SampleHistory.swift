import Foundation

public struct UsageSample: Codable, Equatable, Sendable {
    public let at: Date
    public let utilization: Double
}

/// The app's own record of past readings. The usage endpoint only reports the
/// current percentage, so the "recent rate" half of the pace estimate has to
/// come from what this app has seen itself.
public struct SampleHistory: Codable, Equatable, Sendable {
    public private(set) var session: [UsageSample] = []
    public private(set) var weekly: [UsageSample] = []

    static let keepFor: TimeInterval = 8 * 24 * 3600
    static let minGap: TimeInterval = 60

    public init() {}

    public mutating func record(_ kind: LimitKind, utilization: Double, at date: Date) {
        var samples = self.samples(kind)
        if let last = samples.last, date.timeIntervalSince(last.at) < Self.minGap { return }
        samples.append(UsageSample(at: date, utilization: utilization))
        samples.removeAll { date.timeIntervalSince($0.at) > Self.keepFor }
        switch kind {
        case .session: session = samples
        case .weekly: weekly = samples
        }
    }

    public func samples(_ kind: LimitKind) -> [UsageSample] {
        switch kind {
        case .session: session
        case .weekly: weekly
        }
    }

    /// Percent per second over roughly the last tenth of the window, using only
    /// readings from the current window. Nil until enough time has been observed.
    public func recentRate(_ kind: LimitKind, windowStart: Date, now: Date) -> Double? {
        let lookback = kind.length * 0.1
        let from = max(windowStart, now.addingTimeInterval(-lookback))
        let points = samples(kind).filter { $0.at >= from && $0.at <= now }
        guard let first = points.first, let last = points.last else { return nil }
        let span = last.at.timeIntervalSince(first.at)
        guard span >= lookback * 0.2 else { return nil }
        return max(0, last.utilization - first.utilization) / span
    }
}

extension SampleHistory {
    public static var defaultURL: URL {
        JSONFile.supportDirectory.appendingPathComponent("samples.json")
    }

    public static func load(from url: URL = defaultURL) -> SampleHistory {
        JSONFile.load(SampleHistory.self, from: url) ?? SampleHistory()
    }

    public func save(to url: URL = defaultURL) {
        JSONFile.save(self, to: url)
    }
}
