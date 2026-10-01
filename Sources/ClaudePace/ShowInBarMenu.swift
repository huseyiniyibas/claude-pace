import AppKit
import ClaudePaceCore

/// The "Show in Bar" submenu: for each window, whether it appears in the bar and
/// which of its details do.
///
/// Each row is a check box inside a menu item, not a plain menu item. A plain item
/// closes the whole menu on every click, and the point of this menu is to watch the
/// bar change while ticking boxes. At least one window stays shown, and at least one
/// detail stays ticked per window, so the last box of each such group is greyed out.
@MainActor
final class ShowInBarMenu: NSObject {
    enum Row: Hashable {
        case shown
        case name
        case field(BarField)
    }

    struct Key: Hashable {
        let kind: LimitKind
        let row: Row
    }

    let menu = NSMenu()
    private(set) var buttons: [Key: NSButton] = [:]

    private let read: @MainActor () -> BarOptions
    private let write: @MainActor (BarOptions) -> Void

    private static let rowSize = NSSize(width: 190, height: 22)
    private static let inset: CGFloat = 12

    init(read: @escaping @MainActor () -> BarOptions, write: @escaping @MainActor (BarOptions) -> Void) {
        self.read = read
        self.write = write
        super.init()
        menu.autoenablesItems = false

        for (index, kind) in LimitKind.allCases.enumerated() {
            if index > 0 { menu.addItem(.separator()) }
            menu.addItem(MenuItems.heading(kind.title))
            addRow("Show in bar", Key(kind: kind, row: .shown))
            addRow("Name", Key(kind: kind, row: .name))
            for field in BarField.allCases {
                addRow(field.menuTitle, Key(kind: kind, row: .field(field)))
            }
        }
        refresh()
    }

    func button(_ kind: LimitKind, _ row: Row) -> NSButton? {
        buttons[Key(kind: kind, row: row)]
    }

    /// Brings every box in line with the current options.
    func refresh() {
        let options = read()
        for (key, button) in buttons {
            let window = options[key.kind]
            switch key.row {
            case .shown:
                button.state = window.isShown ? .on : .off
                button.isEnabled = options.canHide(key.kind)
            case .name:
                button.state = window.showsLabel ? .on : .off
            case .field(let field):
                button.state = window.fields.contains(field) ? .on : .off
                button.isEnabled = window.canTurnOff(field)
            }
        }
    }

    private func addRow(_ title: String, _ key: Key) {
        let size = Self.rowSize
        let button = NSButton(checkboxWithTitle: title, target: self, action: #selector(clicked(_:)))
        button.frame = NSRect(x: Self.inset, y: 1, width: size.width - Self.inset, height: size.height - 2)
        buttons[key] = button

        let row = NSView(frame: NSRect(origin: .zero, size: size))
        row.addSubview(button)
        let item = NSMenuItem()
        item.view = row
        menu.addItem(item)
    }

    @objc private func clicked(_ sender: NSButton) {
        guard let key = buttons.first(where: { $0.value === sender })?.key else { return }
        var options = read()
        switch key.row {
        case .shown: options.toggleShown(key.kind)
        case .name: options[key.kind].showsLabel.toggle()
        case .field(let field): options[key.kind].toggle(field)
        }
        write(options)
        refresh()
    }
}
