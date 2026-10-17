//
//  AppUpdatingTests.swift
//  burnbarTests
//
//  The production updaters behind the port: the inert one and the launch composition. The
//  Sparkle adapter has its own suite (`SparkleUpdateCheckerTests`).
//

import Foundation
import Testing
@testable import burnbar

@MainActor
@Suite("App updating")
struct AppUpdatingTests {
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
