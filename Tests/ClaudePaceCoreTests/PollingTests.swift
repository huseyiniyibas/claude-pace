import Foundation
import Testing
@testable import ClaudePaceCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("Poll policy")
struct PollPolicyTests {
    private let policy = PollPolicy()

    @Test("A healthy endpoint is asked every five minutes")
    func healthyInterval() {
        #expect(policy.successInterval == 300)
    }

    @Test("Each consecutive refusal doubles the wait, up to half an hour")
    func rateLimitBacksOff() {
        let waits = (1...6).map { policy.delay(after: .rateLimited(retryAfter: nil), rateLimitStreak: $0) }
        #expect(waits == [300, 600, 1200, 1800, 1800, 1800])
    }

    @Test("A long refusal streak does not overflow")
    func hugeStreak() {
        #expect(policy.delay(after: .rateLimited(retryAfter: nil), rateLimitStreak: 5000) == 1800)
    }

    @Test("The server's Retry-After wins when it asks for longer, but never beyond an hour")
    func retryAfterWins() {
        #expect(policy.delay(after: .rateLimited(retryAfter: 2400), rateLimitStreak: 1) == 2400)
        #expect(policy.delay(after: .rateLimited(retryAfter: 60), rateLimitStreak: 1) == 300)
        #expect(policy.delay(after: .rateLimited(retryAfter: 99_999), rateLimitStreak: 1) == 3600)
    }

    @Test("Network trouble retries sooner than sign-in problems")
    func otherErrors() {
        #expect(policy.delay(after: .network("offline"), rateLimitStreak: 0) == 120)
        #expect(policy.delay(after: .http(503), rateLimitStreak: 0) == 120)
        #expect(policy.delay(after: .tokenExpired, rateLimitStreak: 0) == 300)
        #expect(policy.delay(after: .credentialsNotFound, rateLimitStreak: 0) == 300)
        #expect(policy.delay(after: .unauthorized, rateLimitStreak: 0) == 300)
        #expect(policy.delay(after: .malformed, rateLimitStreak: 0) == 300)
    }
}

@Suite("Poll state")
struct PollStateTests {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("claude-pace-state-\(UUID().uuidString).json")
    }

    private func snapshot(fetchedAt: Date) -> UsageSnapshot {
        UsageSnapshot(
            fiveHour: LimitWindow(utilization: 22, resetsAt: now.addingTimeInterval(3600)),
            sevenDay: LimitWindow(utilization: 79, resetsAt: nil),
            fetchedAt: fetchedAt)
    }

    @Test("No saved file gives an empty state")
    func missingFile() {
        #expect(PollState.load(from: tempURL()) == PollState())
    }

    @Test("State survives a save and load, schedule and reading included")
    func roundTrip() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var state = PollState()
        state.snapshot = snapshot(fetchedAt: now)
        state.lastAttemptAt = now
        state.nextAttemptAt = now.addingTimeInterval(600)
        state.rateLimitStreak = 2
        state.save(to: url)
        #expect(PollState.load(from: url, now: now.addingTimeInterval(60)) == state)
    }

    @Test("A reading older than half an hour is dropped but the schedule is kept")
    func staleReadingDropped() {
        let url = tempURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var state = PollState()
        state.snapshot = snapshot(fetchedAt: now)
        state.nextAttemptAt = now.addingTimeInterval(600)
        state.rateLimitStreak = 1
        state.save(to: url)

        let loaded = PollState.load(from: url, now: now.addingTimeInterval(31 * 60))
        #expect(loaded.snapshot == nil)
        #expect(loaded.nextAttemptAt == now.addingTimeInterval(600))
        #expect(loaded.rateLimitStreak == 1)
    }

    @Test("Manual refresh is closed during a rate limit and right after an attempt")
    func manualRefreshRules() {
        var state = PollState()
        #expect(state.canRefreshManually(now: now))

        state.lastAttemptAt = now.addingTimeInterval(-30)
        #expect(!state.canRefreshManually(now: now))

        state.lastAttemptAt = now.addingTimeInterval(-121)
        #expect(state.canRefreshManually(now: now))

        state.rateLimitStreak = 1
        #expect(!state.canRefreshManually(now: now))
    }
}
