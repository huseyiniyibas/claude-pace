import AppKit
import ClaudePaceCore
import Testing
@testable import ClaudePace

@MainActor
@Suite("Show in Bar menu")
struct ShowInBarMenuTests {
    /// Stands in for the controller: holds the options the menu reads and writes.
    final class Store {
        var options = BarOptions.default
    }

    private func makeMenu(_ store: Store) -> ShowInBarMenu {
        ShowInBarMenu(read: { store.options }, write: { store.options = $0 })
    }

    private func click(_ menu: ShowInBarMenu, _ kind: LimitKind, _ row: ShowInBarMenu.Row) throws {
        try #require(menu.button(kind, row)).performClick(nil)
    }

    @Test("No row is a plain menu item, so a click cannot close the menu")
    func rowsDoNotDismissTheMenu() {
        let menu = makeMenu(Store()).menu
        let rows = menu.items.filter { $0.view != nil }
        #expect(rows.count == LimitKind.allCases.count * (2 + BarField.allCases.count))
        for item in rows { #expect(item.action == nil) }
        for item in menu.items where !item.isSeparatorItem && item.view == nil {
            // Only the greyed-out headings are left, and they cannot be clicked.
            #expect(item.action == nil)
            #expect(!item.isEnabled)
        }
    }

    @Test("The boxes start in line with the default options: all ticked but Time to limit")
    func startsInSync() {
        let menu = makeMenu(Store())
        #expect(menu.buttons.count == 12)
        for (key, button) in menu.buttons {
            let expected: NSControl.StateValue = key.row == .field(.limitIn) ? .off : .on
            #expect(button.state == expected)
        }
    }

    @Test("Time to limit can be ticked on its own for each window")
    func limitInBox() throws {
        let store = Store()
        let menu = makeMenu(store)
        try click(menu, .session, .field(.limitIn))
        #expect(store.options.session.fields == WindowOptions.defaultFields.union([.limitIn]))
        #expect(store.options.weekly.fields == WindowOptions.defaultFields)
        #expect(menu.button(.session, .field(.limitIn))?.state == .on)
        #expect(menu.button(.weekly, .field(.limitIn))?.state == .off)
    }

    @Test("The name box of one window leaves the other window alone")
    func nameIsPerWindow() throws {
        let store = Store()
        let menu = makeMenu(store)
        try click(menu, .session, .name)
        #expect(store.options.session.showsLabel == false)
        #expect(store.options.weekly.showsLabel == true)
        #expect(menu.button(.weekly, .name)?.state == .on)
    }

    @Test("Details are independent per window")
    func fieldsArePerWindow() throws {
        let store = Store()
        let menu = makeMenu(store)
        try click(menu, .weekly, .field(.percent))
        #expect(store.options.weekly.fields == [.timeLeft, .keyword])
        #expect(store.options.session.fields == WindowOptions.defaultFields)
        #expect(menu.button(.session, .field(.percent))?.state == .on)
    }

    @Test("Hiding a window leaves the other's settings as they were")
    func hideOne() throws {
        let store = Store()
        let menu = makeMenu(store)
        try click(menu, .session, .shown)
        #expect(store.options.session.isShown == false)
        #expect(store.options.weekly == WindowOptions())
        // Now only Total is shown, so it can no longer be hidden.
        #expect(menu.button(.weekly, .shown)?.isEnabled == false)
        #expect(menu.button(.session, .shown)?.isEnabled == true)
    }

    @Test("The last ticked detail of each window is greyed out, per window")
    func lastDetailIsPerWindow() throws {
        let store = Store()
        let menu = makeMenu(store)
        try click(menu, .session, .field(.percent))
        try click(menu, .session, .field(.timeLeft))
        #expect(store.options.session.fields == [.keyword])
        #expect(menu.button(.session, .field(.keyword))?.isEnabled == false)
        // Total still has all three, so none of its boxes is locked.
        #expect(menu.button(.weekly, .field(.keyword))?.isEnabled == true)
    }

    @Test("Refreshing picks up options that changed elsewhere")
    func refreshFollowsOptions() {
        let store = Store()
        let menu = makeMenu(store)
        store.options = BarOptions(
            session: WindowOptions(isShown: false, showsLabel: false, fields: [.keyword]),
            weekly: WindowOptions())
        menu.refresh()
        #expect(menu.button(.session, .shown)?.state == .off)
        #expect(menu.button(.session, .name)?.state == .off)
        #expect(menu.button(.session, .field(.percent))?.state == .off)
        #expect(menu.button(.session, .field(.keyword))?.state == .on)
        #expect(menu.button(.weekly, .name)?.state == .on)
    }
}
