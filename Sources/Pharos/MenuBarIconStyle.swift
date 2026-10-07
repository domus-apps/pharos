import Foundation

/* The status item's look, as an idle/active SF Symbol pair — active is
   always the filled variant so the awake state stays readable at a glance
   regardless of the chosen motif. Persisted by rawValue, so cases may be
   added freely but existing names must not change. */
enum MenuBarIconStyle: String, CaseIterable {
    case beacon
    case sun
    case eye
    case cup

    var title: String {
        switch self {
        case .beacon: L("Beacon")
        case .sun: L("Sun")
        case .eye: L("Eye")
        case .cup: L("Coffee Cup")
        }
    }

    var idleSymbolName: String {
        switch self {
        case .beacon: "light.beacon.min"
        case .sun: "sun.min"
        case .eye: "eye"
        case .cup: "cup.and.saucer"
        }
    }

    var activeSymbolName: String {
        switch self {
        case .beacon: "light.beacon.max.fill"
        case .sun: "sun.max.fill"
        case .eye: "eye.fill"
        case .cup: "cup.and.saucer.fill"
        }
    }
}
