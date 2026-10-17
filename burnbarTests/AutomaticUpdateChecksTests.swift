//
//  AutomaticUpdateChecksTests.swift
//  burnbarTests
//
//  The automatic-check preference, against a scratch defaults suite so a test run never reads
//  or writes the developer's real preferences.
//

import Foundation
import Testing
@testable import burnbar

@Suite("Automatic update checks")
struct AutomaticUpdateChecksTests {
    /// A defaults domain that exists only for this test, and is removed after it.
    private func withScratchSuite(_ body: (UserDefaults, String) throws -> Void) rethrows {
        let name = "burnbar-tests-updates-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            Issue.record("could not create the scratch defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults, name)
    }

    /// A missing key reads `false`: an update check is network egress, and "we never asked"
    /// must not be storable as "they said yes".
    @Test func aFreshInstallReadsAsOff() {
        withScratchSuite { defaults, _ in
            let preference = AutomaticUpdateChecks(defaults: defaults)

            #expect(defaults.object(forKey: AutomaticUpdateChecks.key) == nil)
            #expect(preference.isEnabled == false)
        }
    }

    /// A second instance over the same suite makes this a persistence test, not a property test.
    @Test func theChoiceSurvivesARelaunchInBothDirections() {
        withScratchSuite { defaults, name in
            AutomaticUpdateChecks(defaults: defaults).isEnabled = true
            #expect(AutomaticUpdateChecks(defaults: UserDefaults(suiteName: name) ?? defaults).isEnabled)

            AutomaticUpdateChecks(defaults: defaults).isEnabled = false
            #expect(AutomaticUpdateChecks(defaults: UserDefaults(suiteName: name) ?? defaults).isEnabled == false)
        }
    }

    /// Turning it off stores `false` rather than removing the key.
    @Test func turningItOffRecordsAStoredFalse() {
        withScratchSuite { defaults, _ in
            let preference = AutomaticUpdateChecks(defaults: defaults)
            preference.isEnabled = true
            preference.isEnabled = false

            #expect(defaults.object(forKey: AutomaticUpdateChecks.key) as? Bool == false)
        }
    }

    /// Exactly one key, named: a stray companion key would fail it.
    @Test func thePreferenceWritesExactlyOneKeyAndNothingElse() {
        withScratchSuite { defaults, name in
            AutomaticUpdateChecks(defaults: defaults).isEnabled = true

            let domain = defaults.persistentDomain(forName: name) ?? [:]
            #expect(domain.keys.sorted() == [AutomaticUpdateChecks.key])
            #expect(AutomaticUpdateChecks.key == "updates.automaticChecksEnabled")
        }
    }
}
