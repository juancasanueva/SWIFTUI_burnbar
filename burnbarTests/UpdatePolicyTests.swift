//
//  UpdatePolicyTests.swift
//  burnbarTests
//
//  The launch-time write of the automatic-check preference and the enablement of
//  "Check for Updates…": both are decisions, asserted over `FakeAppUpdater`.
//

import Foundation
import Testing
@testable import burnbar

@MainActor
@Suite("Update policy")
struct UpdatePolicyTests {
    /// Each case starts from an updater that disagrees with the preference: a policy that only
    /// wrote when it already matched would pass a test that started from agreement.
    @Test(arguments: [true, false])
    func thePersistedPreferenceIsWrittenToTheUpdater(preference: Bool) {
        let updater = FakeAppUpdater(automaticallyChecksForUpdates: !preference)

        AutomaticUpdateChecksPolicy.apply(preference: preference, to: updater)

        #expect(updater.automaticallyChecksForUpdates == preference)
        #expect(updater.automaticWriteCount == 1)
    }

    /// The idempotent case: a "write only when it differs" optimisation would drop the count to 0.
    @Test func anOffRunLeavesAutomaticCheckingOffAndStillWritesOnce() {
        let updater = FakeAppUpdater(automaticallyChecksForUpdates: false)

        AutomaticUpdateChecksPolicy.apply(preference: false, to: updater)

        #expect(updater.automaticallyChecksForUpdates == false)
        #expect(updater.automaticWriteCount == 1)
    }

    @Test(arguments: [true, false])
    func theCommandIsEnabledExactlyWhileTheUpdaterCanCheck(canCheck: Bool) {
        #expect(UpdateCommandEnablement.isEnabled(canCheckForUpdates: canCheck) == canCheck)
    }

    /// Two updaters differing only in their automatic-check flag produce the same enablement.
    @Test func automaticCheckingDoesNotDecideEnablement() {
        let automaticOff = FakeAppUpdater(canCheckForUpdates: true, automaticallyChecksForUpdates: false)
        let automaticOn = FakeAppUpdater(canCheckForUpdates: true, automaticallyChecksForUpdates: true)
        let inFlight = FakeAppUpdater(canCheckForUpdates: false, automaticallyChecksForUpdates: false)

        #expect(UpdateCommandEnablement.isEnabled(canCheckForUpdates: automaticOff.canCheckForUpdates))
        #expect(UpdateCommandEnablement.isEnabled(canCheckForUpdates: automaticOn.canCheckForUpdates))
        #expect(UpdateCommandEnablement.isEnabled(canCheckForUpdates: inFlight.canCheckForUpdates) == false)
    }
}
