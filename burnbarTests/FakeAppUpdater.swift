//
//  FakeAppUpdater.swift
//  burnbarTests
//
//  In-memory `AppUpdating` double: the whole updater contract runs without Sparkle, without a
//  network and without a real bundle. Counters, because "exactly one check" and "written exactly
//  once" are claims about how many times something happened.
//

import Foundation
import Observation
@testable import burnbar

@MainActor
@Observable
final class FakeAppUpdater: AppUpdating {
    private(set) var checkCount = 0

    var canCheckForUpdates: Bool

    private(set) var lastUpdateCheckDate: Date?

    /// How many times the automatic-check flag was written, not merely its final value.
    @ObservationIgnored private(set) var automaticWriteCount = 0

    @ObservationIgnored private var storedAutomaticChecks: Bool

    var automaticallyChecksForUpdates: Bool {
        get { storedAutomaticChecks }
        set {
            storedAutomaticChecks = newValue
            automaticWriteCount += 1
        }
    }

    init(canCheckForUpdates: Bool = true, automaticallyChecksForUpdates: Bool = false) {
        self.canCheckForUpdates = canCheckForUpdates
        self.storedAutomaticChecks = automaticallyChecksForUpdates
    }

    func checkForUpdates() {
        checkCount += 1
    }

    /// Moves the last-checked date without running a real check.
    func recordCheck(at date: Date) {
        lastUpdateCheckDate = date
    }
}
