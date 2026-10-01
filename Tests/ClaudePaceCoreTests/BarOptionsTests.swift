import Foundation
import Testing
@testable import ClaudePaceCore

private func scratchDefaults() throws -> (UserDefaults, cleanup: () -> Void) {
    let name = "claude-pace-test-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: name))
    return (defaults, { defaults.removePersistentDomain(forName: name) })
}

@Suite("Bar options")
struct BarOptionsTests {
    @Test("Everything is on for both windows by default")
    func defaults() {
        for kind in LimitKind.allCases {
            let window = BarOptions.default[kind]
            #expect(window.isShown)
            #expect(window.showsLabel)
            #expect(window.fields == [.percent, .timeLeft, .keyword])
        }
    }

    @Test("Each window keeps its own name switch")
    func labelIsPerWindow() {
        var options = BarOptions.default
        options[.session].showsLabel = false
        #expect(options.session.showsLabel == false)
        #expect(options.weekly.showsLabel == true)
    }

    @Test("Each window keeps its own details")
    func fieldsArePerWindow() {
        var options = BarOptions.default
        options[.weekly].toggle(.percent)
        #expect(options.weekly.fields == [.timeLeft, .keyword])
        #expect(options.session.fields == [.percent, .timeLeft, .keyword])
        options[.weekly].toggle(.percent)
        #expect(options.weekly.fields == [.percent, .timeLeft, .keyword])
    }

    @Test("The last ticked detail of a window cannot be switched off")
    func keepsOneField() {
        var window = WindowOptions(fields: [.keyword])
        window.toggle(.keyword)
        #expect(window.fields == [.keyword])
        #expect(!window.canTurnOff(.keyword))
        #expect(window.canTurnOff(.percent))
    }

    @Test("A window can be hidden and shown again, but not the last one shown")
    func hidingWindows() {
        var options = BarOptions.default
        options.toggleShown(.session)
        #expect(!options.session.isShown)
        #expect(options.weekly.isShown)
        #expect(!options.canHide(.weekly))

        options.toggleShown(.weekly)
        #expect(options.weekly.isShown)

        options.toggleShown(.session)
        #expect(options.session.isShown)
        #expect(options.canHide(.weekly))
    }

    @Test("A hidden window keeps its settings")
    func hiddenKeepsSettings() {
        var options = BarOptions.default
        options[.session].showsLabel = false
        options[.session].toggle(.percent)
        options.toggleShown(.session)
        options.toggleShown(.session)
        #expect(options.session.showsLabel == false)
        #expect(options.session.fields == [.timeLeft, .keyword])
    }
}

@Suite("Bar options storage")
struct BarOptionsStorageTests {
    @Test("Different choices per window survive a save and load")
    func persists() throws {
        let (defaults, cleanup) = try scratchDefaults()
        defer { cleanup() }

        let chosen = BarOptions(
            session: WindowOptions(isShown: true, showsLabel: false, fields: [.keyword]),
            weekly: WindowOptions(isShown: false, showsLabel: true, fields: [.percent, .timeLeft]))
        chosen.save(to: defaults)
        #expect(BarOptions.load(from: defaults) == chosen)
    }

    @Test("Settings from before windows had their own switches are carried over")
    func legacyShared() throws {
        let (defaults, cleanup) = try scratchDefaults()
        defer { cleanup() }

        let legacy = #"{"windows": ["weekly"], "fields": ["percent", "keyword"], "showsLabel": false}"#
        defaults.set(Data(legacy.utf8), forKey: "barOptions")
        let loaded = BarOptions.load(from: defaults)
        #expect(loaded.session.isShown == false)
        #expect(loaded.weekly.isShown == true)
        #expect(loaded.weekly.fields == [.percent, .keyword])
        #expect(loaded.weekly.showsLabel == false)
        #expect(loaded.session.showsLabel == false)
    }

    @Test("The oldest settings, with no name switch, keep the names")
    func legacyWithoutLabel() throws {
        let (defaults, cleanup) = try scratchDefaults()
        defer { cleanup() }

        let legacy = #"{"windows": ["session", "weekly"], "fields": ["timeLeft"]}"#
        defaults.set(Data(legacy.utf8), forKey: "barOptions")
        let loaded = BarOptions.load(from: defaults)
        #expect(loaded.session.showsLabel)
        #expect(loaded.weekly.showsLabel)
        #expect(loaded.session.fields == [.timeLeft])
    }

    @Test("Nothing stored, or something unreadable, gives the defaults")
    func fallsBackToDefaults() throws {
        let (defaults, cleanup) = try scratchDefaults()
        defer { cleanup() }

        #expect(BarOptions.load(from: defaults) == .default)
        defaults.set(Data("garbage".utf8), forKey: "barOptions")
        #expect(BarOptions.load(from: defaults) == .default)
    }

    @Test("A stored window with no details is repaired")
    func repairsEmptyFields() throws {
        let (defaults, cleanup) = try scratchDefaults()
        defer { cleanup() }

        BarOptions(
            session: WindowOptions(fields: []),
            weekly: WindowOptions(fields: [.percent])).save(to: defaults)
        let loaded = BarOptions.load(from: defaults)
        #expect(loaded.session.fields == WindowOptions.defaultFields)
        #expect(loaded.weekly.fields == [.percent])
    }

    @Test("A stored choice that hides every window is repaired")
    func repairsNoWindows() throws {
        let (defaults, cleanup) = try scratchDefaults()
        defer { cleanup() }

        BarOptions(
            session: WindowOptions(isShown: false),
            weekly: WindowOptions(isShown: false)).save(to: defaults)
        let loaded = BarOptions.load(from: defaults)
        #expect(loaded.session.isShown)
        #expect(loaded.weekly.isShown)
    }
}
