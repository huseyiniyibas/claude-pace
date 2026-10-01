import AppKit

@MainActor
enum MenuItems {
    /// A bold, greyed-out line that titles a group of rows.
    static func heading(_ text: String) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = NSAttributedString(
            string: text, attributes: [.font: NSFont.menuFont(ofSize: 0).bold])
        item.isEnabled = false
        return item
    }
}

private extension NSFont {
    var bold: NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}
