import Foundation
import IOKit.pwr_mgt
import Testing

@testable import Pharos

// MARK: - Countdown formatting

@Test func minutesOnlyBelowAnHour() {
    #expect(AwakeCountdown.remainingLabel(seconds: 45 * 60) == "45 min")
    #expect(AwakeCountdown.remainingLabel(seconds: 60) == "1 min")
}

@Test func wholeHoursDropTheMinutes() {
    #expect(AwakeCountdown.remainingLabel(seconds: 3_600) == "1 hr")
    #expect(AwakeCountdown.remainingLabel(seconds: 7_200) == "2 hr")
}

@Test func hoursAndMinutesCompose() {
    #expect(AwakeCountdown.remainingLabel(seconds: 5_400) == "1 hr 30 min")
    #expect(AwakeCountdown.remainingLabel(seconds: 3_661) == "1 hr 2 min")
}

@Test func partialMinutesRoundUp() {
    /* 59s of a live timer must read "1 min", never "0 min". */
    #expect(AwakeCountdown.remainingLabel(seconds: 59) == "1 min")
    #expect(AwakeCountdown.remainingLabel(seconds: 61) == "2 min")
}

@Test func expiredOrNegativeClampsToOneMinute() {
    /* The timer fires and deactivates at expiry; if the label is ever
       rendered a beat late it should degrade gracefully, not show "0 min"
       or "-1 min". */
    #expect(AwakeCountdown.remainingLabel(seconds: 0) == "1 min")
    #expect(AwakeCountdown.remainingLabel(seconds: -30) == "1 min")
}

// MARK: - Duration presets

@Test func presetSecondsMatchTheirTitles() {
    #expect(AwakeDuration.thirtyMinutes.seconds == 1_800)
    #expect(AwakeDuration.oneHour.seconds == 3_600)
    #expect(AwakeDuration.eightHours.seconds == 28_800)
}

@Test func presetsAreOrderedShortestFirst() {
    let seconds = AwakeDuration.allCases.map(\.seconds)
    #expect(seconds == seconds.sorted())
}

// MARK: - Assertion type selection

@Test func displayAwakeSelectsTheDisplayAssertion() {
    #expect(
        SleepGuard.assertionType(keepingDisplayAwake: true)
            == kIOPMAssertionTypePreventUserIdleDisplaySleep)
    #expect(
        SleepGuard.assertionType(keepingDisplayAwake: false)
            == kIOPMAssertionTypePreventUserIdleSystemSleep)
}
