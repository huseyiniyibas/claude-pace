import Foundation
import Testing
@testable import ClaudePaceCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func estimate(
    used: Double, left: TimeInterval, kind: LimitKind = .session, recentRate: Double? = nil
) -> PaceEstimate {
    PaceCalculator.estimate(
        utilization: used,
        resetsAt: now.addingTimeInterval(left),
        windowLength: kind.length,
        now: now,
        recentRate: recentRate
    )
}

@Suite("Pace verdicts")
struct PaceTests {
    @Test("77% used with 3h 49m left of 5h burns far too fast")
    func sessionBurningFast() {
        let result = estimate(used: 77, left: 3 * 3600 + 49 * 60)
        #expect(result.verdict == .slowDown)
        #expect(result.projectedAtReset > 300)
        #expect(result.timeToLimit != nil)
    }

    @Test("67% used with 25h 51m left of 7d leaves room")
    func weeklyHasRoomToSpare() {
        let result = estimate(used: 67, left: 25 * 3600 + 51 * 60, kind: .weekly)
        #expect(result.verdict == .speedUp)
        #expect(abs(result.projectedAtReset - 79.2) < 0.5)
        #expect(result.timeToLimit == nil)
    }

    @Test("Halfway through the window at 50% is on pace")
    func onPace() {
        let result = estimate(used: 50, left: 2.5 * 3600)
        #expect(result.verdict == .onPace)
        #expect(abs(result.projectedAtReset - 100) < 0.001)
    }

    @Test("Far less than the even burn is a full send")
    func fullSend() {
        let result = estimate(used: 20, left: 2 * 3600)
        #expect(result.verdict == .fullSend)
    }

    @Test("At 100% the limit is reached whatever the clock says")
    func limitReached() {
        #expect(estimate(used: 100, left: 3600).verdict == .limitReached)
    }

    @Test("A fresh window with little used is still warming up")
    func warmingUp() {
        #expect(estimate(used: 1, left: 5 * 3600 - 60).verdict == .warmingUp)
    }

    @Test("A heavy start in a fresh window is not hidden by the warm-up grace")
    func heavyStartIsNotWarmup() {
        #expect(estimate(used: 40, left: 5 * 3600 - 60).verdict == .slowDown)
    }

    @Test("An idle recent stretch pulls the projection down")
    func recentRateBlends() {
        let average = estimate(used: 50, left: 2.5 * 3600)
        let idle = estimate(used: 50, left: 2.5 * 3600, recentRate: 0)
        #expect(idle.projectedAtReset < average.projectedAtReset)
        #expect(abs(idle.projectedAtReset - 75) < 0.001)
    }

    @Test("A burst pushes the projection up")
    func recentBurst() {
        let burst = estimate(used: 50, left: 2.5 * 3600, recentRate: 0.01)
        #expect(burst.verdict == .slowDown)
    }

    @Test("A stale window past its reset projects exactly what is used")
    func pastReset() {
        let result = estimate(used: 40, left: -600)
        #expect(result.remaining == 0)
        #expect(result.projectedAtReset == 40)
    }
}

@Suite("Recent rate from history")
struct HistoryTests {
    @Test("No rate until enough time has been observed")
    func needsSpan() {
        var history = SampleHistory()
        history.record(.session, utilization: 10, at: now.addingTimeInterval(-120))
        history.record(.session, utilization: 12, at: now)
        #expect(history.recentRate(.session, windowStart: now.addingTimeInterval(-3600), now: now) == nil)
    }

    @Test("Rate is percent per second across the lookback")
    func computesRate() {
        var history = SampleHistory()
        history.record(.session, utilization: 10, at: now.addingTimeInterval(-1200))
        history.record(.session, utilization: 16, at: now)
        let rate = history.recentRate(.session, windowStart: now.addingTimeInterval(-3600), now: now)
        #expect(rate != nil)
        #expect(abs((rate ?? 0) - 6.0 / 1200.0) < 1e-9)
    }

    @Test("Readings from before the window started are ignored")
    func ignoresPreviousWindow() {
        var history = SampleHistory()
        history.record(.session, utilization: 95, at: now.addingTimeInterval(-1500))
        history.record(.session, utilization: 2, at: now.addingTimeInterval(-600))
        history.record(.session, utilization: 4, at: now)
        let rate = history.recentRate(.session, windowStart: now.addingTimeInterval(-700), now: now)
        // Only the two post-reset readings span 600s, below the 20% of 1800s lookback minimum? 600 >= 360, so a rate exists.
        #expect(abs((rate ?? 0) - 2.0 / 600.0) < 1e-9)
    }

    @Test("Samples closer than a minute apart are not stored twice")
    func throttlesSamples() {
        var history = SampleHistory()
        history.record(.weekly, utilization: 1, at: now)
        history.record(.weekly, utilization: 2, at: now.addingTimeInterval(10))
        #expect(history.samples(.weekly).count == 1)
    }

    @Test("History survives a save and load")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-pace-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var history = SampleHistory()
        history.record(.session, utilization: 33, at: now)
        history.save(to: url)
        #expect(SampleHistory.load(from: url) == history)
    }
}
