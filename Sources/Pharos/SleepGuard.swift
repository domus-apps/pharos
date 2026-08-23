import Foundation
import IOKit.pwr_mgt

/* Prevents sleep through an IOKit power assertion — the same public API
   `caffeinate` uses. No entitlements, no permissions, no private frameworks:
   the assertion simply exists while Pharos holds it and vanishes when the
   process exits, so there is no failure mode that leaves the Mac stuck
   awake after a crash. */
final class SleepGuard {
    private var assertionID: IOPMAssertionID = 0
    private(set) var isActive = false

    /* PreventUserIdleDisplaySleep implies system sleep prevention too, so
       the two preferences collapse into one assertion type. */
    static func assertionType(keepingDisplayAwake: Bool) -> String {
        keepingDisplayAwake
            ? kIOPMAssertionTypePreventUserIdleDisplaySleep
            : kIOPMAssertionTypePreventUserIdleSystemSleep
    }

    /* Idempotent: re-activating (e.g. after the display preference changes)
       swaps the assertion without a gap mattering — losing the assertion for
       a microsecond can't put the Mac to sleep. */
    @discardableResult
    func activate(keepingDisplayAwake: Bool) -> Bool {
        deactivate()
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            Self.assertionType(keepingDisplayAwake: keepingDisplayAwake) as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Pharos is keeping the Mac awake" as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            assertionID = id
            isActive = true
        } else {
            NSLog("Pharos: power assertion failed (IOReturn \(result))")
        }
        return isActive
    }

    func deactivate() {
        guard isActive else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        isActive = false
    }

    deinit {
        deactivate()
    }
}
