import Foundation

public enum DurationFormat {
    /// "3h 49m", "25h 51m", "42m", "<1m". Hours keep counting past 24 so a
    /// weekly window reads "25h 51m" rather than "1d 1h".
    public static func left(_ interval: TimeInterval) -> String {
        guard interval >= 60 else { return "<1m" }
        let totalMinutes = Int(interval / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)m" }
        return "\(hours)h \(minutes)m"
    }
}
