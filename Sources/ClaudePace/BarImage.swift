import AppKit

/// Draws the bar text offscreen as a PNG, for the README. A real screenshot cannot
/// show the full bar on a Mac with a notch, where macOS hides items that do not fit.
@MainActor
enum BarImage {
    /// The text on a rounded, menu-bar-coloured pill, drawn as the light or dark
    /// appearance would draw it, whatever the Mac itself is set to. The caller sets
    /// `NSApplication.shared.appearance` to the same appearance first: system colours
    /// are resolved against the app's appearance, not the one asked for here.
    static func png(for title: NSAttributedString, dark: Bool, scale: CGFloat = 2) -> Data? {
        guard let appearance = NSAppearance(named: dark ? .darkAqua : .aqua) else { return nil }
        let text = resolved(title, in: appearance)
        let padding = NSSize(width: 12, height: 7)
        let textSize = text.size()
        let size = NSSize(
            width: ceil(textSize.width) + padding.width * 2,
            height: ceil(textSize.height) + padding.height * 2)

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        // The size in points has to be set before the context is made, or drawing
        // is in pixels and the picture comes out at half scale.
        bitmap.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        (dark ? NSColor(white: 0.17, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 9, yRadius: 9).fill()
        text.draw(at: NSPoint(x: padding.width, y: padding.height))
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    /// System colours such as the label colour change with the appearance. Drawing
    /// text does not resolve them for an appearance chosen here, so fix them first.
    private static func resolved(_ title: NSAttributedString, in appearance: NSAppearance) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: title)
        appearance.performAsCurrentDrawingAppearance {
            result.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: result.length)) { value, range, _ in
                guard let color = value as? NSColor, let fixed = NSColor(cgColor: color.cgColor) else { return }
                result.addAttribute(.foregroundColor, value: fixed, range: range)
            }
        }
        return result
    }
}
