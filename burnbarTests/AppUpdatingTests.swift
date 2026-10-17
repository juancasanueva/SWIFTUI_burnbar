//
//  AppUpdatingTests.swift
//  burnbarTests
//
//  The updater port, driven over `FakeAppUpdater` and the inert `InMemoryAppUpdater`.
//

import Foundation
import Testing
@testable import burnbar

@MainActor
@Suite("App updating")
struct AppUpdatingTests {
    /// Two invocations as well as one: ignoring the call satisfies "not more than one", and
    /// latching after the first satisfies "at least one".
    @Test func eachInvocationStartsExactlyOneCheck() {
        let updater = FakeAppUpdater()

        #expect(updater.checkCount == 0)
        updater.checkForUpdates()
        #expect(updater.checkCount == 1)
        updater.checkForUpdates()
        #expect(updater.checkCount == 2)
    }

    /// The launch wiring writes the flag and the setup toggle reads it back.
    @Test func theAutomaticCheckFlagRoundTrips() {
        let updater = FakeAppUpdater(automaticallyChecksForUpdates: false)

        #expect(updater.automaticallyChecksForUpdates == false)
        updater.automaticallyChecksForUpdates = true
        #expect(updater.automaticallyChecksForUpdates)
        updater.automaticallyChecksForUpdates = false
        #expect(updater.automaticallyChecksForUpdates == false)
    }

    /// Whether a check can run is unrelated to whether automatic checking is on.
    @Test func whetherACheckCanRunIsIndependentOfAutomaticChecking() {
        let idle = FakeAppUpdater(canCheckForUpdates: true, automaticallyChecksForUpdates: false)
        let inFlight = FakeAppUpdater(canCheckForUpdates: false, automaticallyChecksForUpdates: true)

        #expect(idle.canCheckForUpdates)
        #expect(idle.automaticallyChecksForUpdates == false)
        #expect(inFlight.canCheckForUpdates == false)
        #expect(inFlight.automaticallyChecksForUpdates)
    }

    /// A fresh updater has never checked and says so through the seam.
    @Test func theRecordedCheckDateFollowsARecordedCheck() {
        let updater = FakeAppUpdater()
        let checked = Date(timeIntervalSince1970: 1_787_000_000)

        #expect(updater.lastUpdateCheckDate == nil)
        updater.recordCheck(at: checked)
        #expect(updater.lastUpdateCheckDate == checked)
    }

    /// Inert runs (tests, UI tests) get an updater that never reaches the network: checking does
    /// nothing, the flag only lives in memory, and it has never checked.
    @Test func theInertUpdaterNeverChecks() {
        let updater = InMemoryAppUpdater(automaticallyChecksForUpdates: true)

        updater.checkForUpdates()

        #expect(updater.canCheckForUpdates)
        #expect(updater.automaticallyChecksForUpdates)
        #expect(updater.lastUpdateCheckDate == nil)
        updater.automaticallyChecksForUpdates = false
        #expect(updater.automaticallyChecksForUpdates == false)
    }
}

@MainActor
@Suite("Updater composition")
struct UpdaterCompositionTests {
    /// The inert composition never builds the Sparkle adapter.
    @Test func inertRunsGetTheInMemoryUpdater() {
        #expect(burnbarApp.makeUpdater(isInert: true) is InMemoryAppUpdater)
    }
}
