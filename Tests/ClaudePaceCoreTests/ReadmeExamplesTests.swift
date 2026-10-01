import Foundation
import Testing
@testable import ClaudePaceCore

/// Builds the bar examples in the README from the code itself, so they cannot drift
/// from what the app really shows. Every example uses the same numbers: Session at
/// 77% with 3h 49m left, and Total at 67% with 25h 51m left.
enum ReadmeExamples {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static let report: UsageReport = {
        let snapshot = UsageSnapshot(
            fiveHour: LimitWindow(utilization: 77, resetsAt: now.addingTimeInterval(3 * 3600 + 49 * 60)),
            sevenDay: LimitWindow(utilization: 67, resetsAt: now.addingTimeInterval(25 * 3600 + 51 * 60)),
            fetchedAt: now)
        return UsageReport(snapshot: snapshot, history: SampleHistory(), now: now)
    }()

    /// Every non-empty choice of the original three details, in reading order.
    static let basicSets: [Set<BarField>] = [
        [.percent], [.timeLeft], [.keyword],
        [.percent, .timeLeft], [.percent, .keyword], [.timeLeft, .keyword],
        [.percent, .timeLeft, .keyword],
    ]

    /// The same, with Time to limit added, and Time to limit on its own.
    static let limitSets: [Set<BarField>] = [
        [.limitIn],
        [.percent, .limitIn], [.timeLeft, .limitIn], [.limitIn, .keyword],
        [.percent, .timeLeft, .limitIn], [.percent, .limitIn, .keyword], [.timeLeft, .limitIn, .keyword],
        [.percent, .timeLeft, .limitIn, .keyword],
    ]

    static func title(_ fields: Set<BarField>) -> String {
        BarField.allCases.filter(fields.contains).map(\.menuTitle).joined(separator: " + ")
    }

    static func bar(session: WindowOptions, weekly: WindowOptions) -> String {
        report.barText(options: BarOptions(session: session, weekly: weekly))
    }

    /// One group per choice of details: the Session segment, the Total segment, and
    /// the bar when both windows use that choice.
    static func block(_ sets: [Set<BarField>], showsName: Bool) -> String {
        let hidden = WindowOptions(isShown: false)
        return sets.map { fields in
            let window = WindowOptions(showsLabel: showsName, fields: fields)
            return [
                title(fields),
                "  Session  " + bar(session: window, weekly: hidden),
                "  Total    " + bar(session: hidden, weekly: window),
                "  Both     " + bar(session: window, weekly: window),
            ].joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    /// Setups where the two windows are not alike.
    static func mixedBlock() -> String {
        let hidden = WindowOptions(isShown: false)
        let cases: [(String, WindowOptions, WindowOptions)] = [
            ("Session: keyword only, no name.  Total: name, percentage, time left.",
             WindowOptions(showsLabel: false, fields: [.keyword]),
             WindowOptions(fields: [.percent, .timeLeft])),
            ("Session: name, percentage, time to limit.  Total: hidden.",
             WindowOptions(fields: [.percent, .limitIn]), hidden),
            ("Session: hidden.  Total: keyword only, no name.",
             hidden, WindowOptions(showsLabel: false, fields: [.keyword])),
            ("Session: percentage and keyword, no name.  Total: name and keyword.",
             WindowOptions(showsLabel: false, fields: [.percent, .keyword]),
             WindowOptions(fields: [.keyword])),
            ("Both windows: no names, keyword only.",
             WindowOptions(showsLabel: false, fields: [.keyword]),
             WindowOptions(showsLabel: false, fields: [.keyword])),
        ]
        return cases.map { text, session, weekly in
            [text, "  " + bar(session: session, weekly: weekly)].joined(separator: "\n")
        }.joined(separator: "\n\n")
    }

    /// The Markdown that goes between the markers in README.md.
    static func section() -> String {
        """
        #### Window name on

        Percentage, Time left and Pace keyword in every combination, with the window's name in front.

        ```text
        \(block(basicSets, showsName: true))
        ```

        #### Window name off

        The same combinations without the name.

        ```text
        \(block(basicSets, showsName: false))
        ```

        #### With Time to limit

        Time to limit is switched off by default. Here it is added to every combination, with the name on. It only appears while the limit would be reached before the window resets, which is the case for Session in these numbers and not for Total, so Total shows nothing extra. If Time to limit is the only detail chosen and does not apply, the bar shows the percentage instead of nothing.

        ```text
        \(block(limitSets, showsName: true))
        ```

        #### Different settings per window

        Each window has its own settings, so the two can be set up differently in the same bar.

        ```text
        \(mixedBlock())
        ```
        """
    }
}

@Suite("README examples")
struct ReadmeExamplesTests {
    private static let start = "<!-- examples:start -->"
    private static let end = "<!-- examples:end -->"

    /// To refresh the README after changing how the bar reads:
    /// `UPDATE_README=1 swift test --filter ReadmeExamples`
    @Test("The bar examples in the README are exactly what the code prints")
    func upToDate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("README.md")
        // A copy of the sources without the README has nothing to check.
        guard let readme = try? String(contentsOf: url, encoding: .utf8) else { return }

        let startRange = try #require(readme.range(of: Self.start), "README.md has no \(Self.start) marker")
        let endRange = try #require(readme.range(of: Self.end), "README.md has no \(Self.end) marker")
        let expected = "\n\n" + ReadmeExamples.section() + "\n\n"

        if ProcessInfo.processInfo.environment["UPDATE_README"] != nil {
            var updated = readme
            updated.replaceSubrange(startRange.upperBound..<endRange.lowerBound, with: expected)
            try updated.write(to: url, atomically: true, encoding: .utf8)
            return
        }
        let current = String(readme[startRange.upperBound..<endRange.lowerBound])
        #expect(current == expected, "Run `UPDATE_README=1 swift test --filter ReadmeExamples` to refresh the README examples.")
    }

    @Test("Every combination of the three original details is covered, name on and off")
    func coversEveryCombination() {
        #expect(ReadmeExamples.basicSets.count == 7)
        #expect(Set(ReadmeExamples.basicSets).count == 7)
        #expect(ReadmeExamples.limitSets.count == 8)
        // 2 name choices x 7 sets, plus the Time to limit sets with the name on.
        let groups = ReadmeExamples.basicSets.count * 2 + ReadmeExamples.limitSets.count
        #expect(groups == 22)
    }
}
