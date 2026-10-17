//
//  SparkleUpdateChecker.swift
//  burnbar
//
//  The only file that imports Sparkle (asserted by `UpdateProjectFileTests`). The feed and the
//  verification key are build-time facts merged into the bundle from `Burnbar-Info.plist`;
//  this type offers no way to override either at run time.
//

import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class SparkleUpdateChecker: AppUpdating {
    private(set) var canCheckForUpdates: Bool
    private(set) var lastUpdateCheckDate: Date?

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private let automaticChecks: AutomaticUpdateChecks
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
    @ObservationIgnored private var lastCheckObservation: NSKeyValueObservation?

    /// The app's preference is applied before the updater starts, which is why the controller
    /// is created with `startingUpdater: false`: otherwise Sparkle asks on second launch whether
    /// to enable automatic checks, on a machine where the user may already have said no.
    init(automaticChecks: AutomaticUpdateChecks) {
        self.automaticChecks = automaticChecks
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        self.controller = controller
        self.canCheckForUpdates = controller.updater.canCheckForUpdates
        self.lastUpdateCheckDate = controller.updater.lastUpdateCheckDate

        AutomaticUpdateChecksPolicy.apply(preference: automaticChecks.isEnabled, to: self)
        controller.startUpdater()

        observeUpdater()
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            access(keyPath: \.automaticallyChecksForUpdates)
            return automaticChecks.isEnabled
        }
        set {
            withMutation(keyPath: \.automaticallyChecksForUpdates) {
                // Sparkle first, the app's key second: a crash in between leaves the authority
                // holding the old answer, which the next launch re-applies.
                controller.updater.automaticallyChecksForUpdates = newValue
                automaticChecks.isEnabled = newValue
            }
        }
    }

    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// Mirrors the two values the surfaces read into Observation. Sparkle mutates both on the
    /// main thread, so `assumeIsolated` holds; a hop would leave the command briefly enabled
    /// while a check is already running.
    private func observeUpdater() {
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.canCheckForUpdates = self.controller.updater.canCheckForUpdates
            }
        }
        lastCheckObservation = controller.updater.observe(\.lastUpdateCheckDate, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.lastUpdateCheckDate = self.controller.updater.lastUpdateCheckDate
            }
        }
    }
}
