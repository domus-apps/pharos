import Foundation

/* The "Keep Awake For" presets. Raw value is the duration in seconds, which
   doubles as the NSMenuItem tag. */
enum AwakeDuration: Int, CaseIterable {
    case thirtyMinutes = 1_800
    case oneHour = 3_600
    case twoHours = 7_200
    case fourHours = 14_400
    case eightHours = 28_800

    var title: String {
        switch self {
        case .thirtyMinutes: L("30 Minutes")
        case .oneHour: L("1 Hour")
        case .twoHours: L("2 Hours")
        case .fourHours: L("4 Hours")
        case .eightHours: L("8 Hours")
        }
    }

    var seconds: TimeInterval { TimeInterval(rawValue) }
}

/* Pure countdown formatting, kept UI-free so it's unit-testable. */
enum AwakeCountdown {
    /// "1 hr 30 min", "2 hr", "45 min". Minutes round UP so an active timer
    /// never reads "0 min" — with time on the clock, at least "1 min" shows.
    static func remainingLabel(seconds: TimeInterval) -> String {
        let minutes = max(Int((seconds / 60).rounded(.up)), 1)
        let h = minutes / 60
        let m = minutes % 60
        switch (h, m) {
        case (0, _): return L("%d min", m)
        case (_, 0): return L("%d hr", h)
        default: return L("%1$d hr %2$d min", h, m)
        }
    }
}
