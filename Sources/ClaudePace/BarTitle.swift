import AppKit
import ClaudePaceCore

/// The text the menu bar item shows. The same code draws the bar on screen and the
/// bar images in the README, so the pictures cannot drift from the app.
@MainActor
enum BarTitle {
    /// - Parameter dim: 1 normally; lower when the numbers may be out of date.
    static func make(_ segments: [BarSegment], font: NSFont = .menuBarFont(ofSize: 0), dim: CGFloat = 1) -> NSAttributedString {
        let title = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.labelColor.withAlphaComponent(dim),
        ]
        for (index, segment) in segments.enumerated() {
            if index > 0 { title.append(NSAttributedString(string: UsageReport.segmentSeparator, attributes: base)) }
            title.append(NSAttributedString(string: segment.text, attributes: base))
            if let verdict = segment.verdict {
                title.append(NSAttributedString(string: segment.verdictSeparator, attributes: base))
                title.append(NSAttributedString(string: verdict.label, attributes: [
                    .font: NSFont.systemFont(ofSize: font.pointSize, weight: .semibold),
                    .foregroundColor: color(for: verdict).withAlphaComponent(dim),
                ]))
            }
        }
        return title
    }

    static func color(for verdict: PaceVerdict) -> NSColor {
        switch verdict {
        case .warmingUp: .secondaryLabelColor
        case .limitReached, .slowDown: .systemRed
        case .onPace: .systemGreen
        case .speedUp: .systemTeal
        case .fullSend: .systemBlue
        }
    }
}
