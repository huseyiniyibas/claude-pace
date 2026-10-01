import Foundation
import Testing
@testable import ClaudePaceCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Suite("Duration format")
struct DurationTests {
    @Test("Hours keep counting past a day")
    func hoursPastDay() {
        #expect(DurationFormat.left(25 * 3600 + 51 * 60) == "25h 51m")
        #expect(DurationFormat.left(3 * 3600 + 49 * 60) == "3h 49m")
    }

    @Test("Under an hour shows minutes only; under a minute shows <1m")
    func short() {
        #expect(DurationFormat.left(42 * 60) == "42m")
        #expect(DurationFormat.left(30) == "<1m")
        #expect(DurationFormat.left(0) == "<1m")
    }

}

@Suite("Usage endpoint decoding")
struct DecodingTests {
    // Synthetic body in the endpoint's documented shape; not captured from any account.
    private let body = """
    {
      "five_hour": {"utilization": 77.0, "resets_at": "2027-01-15T08:00:00.123456+00:00"},
      "seven_day": {"utilization": 67, "resets_at": "2027-01-16T10:30:00+00:00"},
      "seven_day_opus": null,
      "seven_day_sonnet": {"utilization": 12.5, "resets_at": null},
      "extra_usage": {"is_enabled": false}
    }
    """

    @Test("Reads windows, tolerates nulls, microseconds and unknown keys")
    func decodes() throws {
        let snapshot = try UsageSnapshot.decode(Data(body.utf8), fetchedAt: now)
        #expect(snapshot.fiveHour?.utilization == 77)
        #expect(snapshot.sevenDay?.utilization == 67)
        #expect(snapshot.sevenDayOpus == nil)
        #expect(snapshot.sevenDaySonnet?.utilization == 12.5)
        #expect(snapshot.sevenDaySonnet?.resetsAt == nil)
        #expect(snapshot.fiveHour?.resetsAt == ISO8601DateFormatter().date(from: "2027-01-15T08:00:00Z"))
    }

    @Test("An unrecognised body is an error, not a blank bar")
    func malformed() {
        #expect(throws: LimitsError.malformed) {
            try UsageSnapshot.decode(Data(#"{"hello": "world"}"#.utf8))
        }
        #expect(throws: LimitsError.malformed) {
            try UsageSnapshot.decode(Data("not json".utf8))
        }
    }

    @Test("Credentials parse to a token and an expiry in milliseconds")
    func credentials() throws {
        let json = #"{"claudeAiOauth": {"accessToken": "fake-token", "refreshToken": "ignored", "expiresAt": 1800000000000}}"#
        let parsed = try CredentialParser.parse(Data(json.utf8))
        #expect(parsed.accessToken == "fake-token")
        #expect(parsed.expiresAt == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test("Credentials without a token are reported as not found")
    func credentialsMissing() {
        #expect(throws: LimitsError.credentialsNotFound) {
            try CredentialParser.parse(Data(#"{"claudeAiOauth": {}}"#.utf8))
        }
    }
}

@Suite("Bar text")
struct BarTextTests {
    private func report(session: (Double, TimeInterval)?, weekly: (Double, TimeInterval)?) -> UsageReport {
        let snapshot = UsageSnapshot(
            fiveHour: session.map { LimitWindow(utilization: $0.0, resetsAt: now.addingTimeInterval($0.1)) },
            sevenDay: weekly.map { LimitWindow(utilization: $0.0, resetsAt: now.addingTimeInterval($0.1)) },
            fetchedAt: now
        )
        return UsageReport(snapshot: snapshot, history: SampleHistory(), now: now)
    }

    @Test("Full bar matches the requested wording")
    func fullBar() {
        let report = report(session: (77, 3 * 3600 + 49 * 60), weekly: (67, 25 * 3600 + 51 * 60))
        #expect(report.barText() == "Session 77% - 3h 49m left | Slow down   Total 67% - 25h 51m left | Speed up")
    }

    @Test("Each window gets its own verdict")
    func independentVerdicts() {
        let report = report(session: (77, 3 * 3600 + 49 * 60), weekly: (20, 25 * 3600 + 51 * 60))
        #expect(report.session?.estimate?.verdict == .slowDown)
        #expect(report.weekly?.estimate?.verdict == .fullSend)
    }

    @Test("A missing window is left out of the bar")
    func missingWindow() {
        let report = report(session: nil, weekly: (67, 25 * 3600 + 51 * 60))
        #expect(report.barText() == "Total 67% - 25h 51m left | Speed up")
    }

    private var both: UsageReport {
        report(session: (77, 3 * 3600 + 49 * 60), weekly: (67, 25 * 3600 + 51 * 60))
    }

    private func options(windows: Set<LimitKind> = [.session, .weekly], fields: Set<BarField>) -> BarOptions {
        BarOptions(windows: windows, fields: fields)
    }

    @Test("Session only and Total only show a single segment")
    func singleWindow() {
        #expect(both.barText(options: options(windows: [.session], fields: WindowOptions.defaultFields))
                == "Session 77% - 3h 49m left | Slow down")
        #expect(both.barText(options: options(windows: [.weekly], fields: WindowOptions.defaultFields))
                == "Total 67% - 25h 51m left | Speed up")
    }

    @Test("Percentage alone")
    func percentOnly() {
        #expect(both.barText(options: options(fields: [.percent])) == "Session 77%   Total 67%")
    }

    @Test("Time left alone")
    func timeOnly() {
        #expect(both.barText(options: options(fields: [.timeLeft]))
                == "Session 3h 49m left   Total 25h 51m left")
    }

    @Test("Keyword alone")
    func keywordOnly() {
        #expect(both.barText(options: options(fields: [.keyword]))
                == "Session | Slow down   Total | Speed up")
    }

    @Test("Any two fields can be combined")
    func twoFields() {
        #expect(both.barText(options: options(fields: [.percent, .keyword]))
                == "Session 77% | Slow down   Total 67% | Speed up")
        #expect(both.barText(options: options(fields: [.percent, .timeLeft]))
                == "Session 77% - 3h 49m left   Total 67% - 25h 51m left")
    }

    private func unlabelled(
        windows: Set<LimitKind> = [.session, .weekly], fields: Set<BarField>
    ) -> BarOptions {
        BarOptions(windows: windows, fields: fields, showsLabel: false)
    }

    @Test("One window's keyword alone, with no name")
    func keywordAloneForOneWindow() {
        #expect(both.barText(options: unlabelled(windows: [.session], fields: [.keyword])) == "Slow down")
        #expect(both.barText(options: unlabelled(windows: [.weekly], fields: [.keyword])) == "Speed up")
    }

    @Test("Without names every field still joins up the same way")
    func unlabelledFields() {
        #expect(both.barText(options: unlabelled(windows: [.session], fields: [.percent, .keyword]))
                == "77% | Slow down")
        #expect(both.barText(options: unlabelled(windows: [.session], fields: [.percent, .timeLeft]))
                == "77% - 3h 49m left")
        #expect(both.barText(options: unlabelled(fields: [.percent])) == "77%   67%")
        #expect(both.barText(options: unlabelled(fields: WindowOptions.defaultFields))
                == "77% - 3h 49m left | Slow down   67% - 25h 51m left | Speed up")
    }

    @Test("A bare keyword is not preceded by a divider")
    func noDanglingDivider() {
        let segment = both.segments(options: unlabelled(windows: [.session], fields: [.keyword]))[0]
        #expect(segment.text.isEmpty)
        #expect(segment.verdictSeparator.isEmpty)
        #expect(segment.verdict == .slowDown)
    }

    @Test("A window with no reset time still shows something when names are off")
    func unlabelledFallback() {
        let snapshot = UsageSnapshot(fiveHour: LimitWindow(utilization: 40, resetsAt: nil), fetchedAt: now)
        let report = UsageReport(snapshot: snapshot, history: SampleHistory(), now: now)
        #expect(report.barText(options: unlabelled(fields: [.keyword])) == "40%")
    }

    @Test("If the chosen window is missing, the bar falls back to what exists")
    func missingChoiceFallsBack() {
        let report = report(session: nil, weekly: (67, 25 * 3600 + 51 * 60))
        #expect(report.barText(options: options(windows: [.session], fields: WindowOptions.defaultFields))
                == "Total 67% - 25h 51m left | Speed up")
    }

    @Test("A window with no reset time shows its percentage whatever fields are chosen")
    func noResetTimeFallsBackToPercent() {
        let snapshot = UsageSnapshot(fiveHour: LimitWindow(utilization: 40, resetsAt: nil), fetchedAt: now)
        let report = UsageReport(snapshot: snapshot, history: SampleHistory(), now: now)
        #expect(report.barText(options: options(fields: [.timeLeft, .keyword])) == "Session 40%")
    }

    @Test("Each window can be set up differently in the same bar")
    func differentPerWindow() {
        // Session: no name, keyword only. Total: with its name, percentage and time.
        let options = BarOptions(
            session: WindowOptions(showsLabel: false, fields: [.keyword]),
            weekly: WindowOptions(showsLabel: true, fields: [.percent, .timeLeft]))
        #expect(both.barText(options: options) == "Slow down   Total 67% - 25h 51m left")
    }

    @Test("Turning the name off for one window keeps it on the other")
    func nameOffForOneWindow() {
        var options = BarOptions.default
        options[.session].showsLabel = false
        #expect(both.barText(options: options)
                == "77% - 3h 49m left | Slow down   Total 67% - 25h 51m left | Speed up")
    }

    @Test("A hidden window is left out whatever its details are")
    func hiddenWindow() {
        var options = BarOptions.default
        options.toggleShown(.session)
        #expect(both.barText(options: options) == "Total 67% - 25h 51m left | Speed up")
    }

    @Test("Time to limit is off by default, so the default bar is unchanged")
    func limitInOffByDefault() {
        #expect(!BarOptions.default.session.fields.contains(.limitIn))
        #expect(!both.barText().contains("limit in"))
    }

    @Test("Time to limit shows how long until the limit at the current pace")
    func limitIn() {
        // 77% used after 1h 11m of 5h: 23 points to go at ~1.08 points a minute is about 21 minutes.
        let options = BarOptions(
            session: WindowOptions(fields: [.limitIn]),
            weekly: WindowOptions(isShown: false))
        #expect(both.barText(options: options) == "Session limit in 21m")
    }

    @Test("Time to limit sits after the time left and before the keyword")
    func limitInOrder() {
        let options = BarOptions(
            session: WindowOptions(fields: Set(BarField.allCases)),
            weekly: WindowOptions(isShown: false))
        #expect(both.barText(options: options)
                == "Session 77% - 3h 49m left - limit in 21m | Slow down")
    }

    @Test("Time to limit is left out when the limit will not be reached before the reset")
    func limitInOmittedWhenSafe() {
        // Total projects to about 79%, so there is no limit to count down to.
        let withOthers = BarOptions(
            session: WindowOptions(isShown: false),
            weekly: WindowOptions(fields: [.percent, .limitIn, .keyword]))
        #expect(both.barText(options: withOthers) == "Total 67% | Speed up")
    }

    @Test("If Time to limit is the only detail and does not apply, the percentage stands in")
    func limitInAloneFallsBack() {
        let options = BarOptions(
            session: WindowOptions(isShown: false),
            weekly: WindowOptions(fields: [.limitIn]))
        #expect(both.barText(options: options) == "Total 67%")
    }

    @Test("Percent rounds to the nearest whole number")
    func rounding() {
        let report = report(session: (76.6, 2 * 3600), weekly: nil)
        #expect(report.session?.percentText == "77%")
    }
}
