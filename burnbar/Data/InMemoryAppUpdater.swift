//
//  InMemoryAppUpdater.swift
//  burnbar
//
//  The updater for inert runs (hosted unit tests, UI tests with `BURNBAR_INERT=1`): Sparkle is
//  never started, so nothing reaches the feed, writes the real preference or opens a window.
//

import Foundation
import Observation

@MainActor
@Observable
final class InMemoryAppUpdater: AppUpdating {
    let canCheckForUpdates = true
    var automaticallyChecksForUpdates: Bool
    let lastUpdateCheckDate: Date? = nil

    init(automaticallyChecksForUpdates: Bool = false) {
        self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
    }

    /// Does nothing: an inert run never checks.
    func checkForUpdates() {}
}
