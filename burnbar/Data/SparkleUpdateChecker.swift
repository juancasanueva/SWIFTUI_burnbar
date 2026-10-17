//
//  SparkleUpdateChecker.swift
//  burnbar
//
//  The only file that imports Sparkle (asserted by `UpdateProjectFileTests`). The feed and the
//  verification key are build-time facts merged into the bundle from `Burnbar-Info.plist`;
//  this file offers no way to override either at run time.
//

import Foundation
import Observation
import Sparkle

/// The few updater members the adapter uses, so its launch order, write order and threading can
/// be tested without starting Sparkle. Production conforms with `SparkleStandardUpdater`.
@MainActor
protocol SparkleUpdaterDriving: AnyObject {
    var canCheckForUpdates: Bool { get }
    var lastUpdateCheckDate: Date? { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func startUpdater()
    func checkForUpdates()
    /// Calls `onChange` whenever `canCheckForUpdates` or `lastUpdateCheckDate` changes, on
    /// whichever thread posted the change. Observation lasts as long as the returned token.
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject
}

@MainActor
@Observable
final class SparkleUpdateChecker: AppUpdating {
    private(set) var canCheckForUpdates: Bool
    private(set) var lastUpdateCheckDate: Date?

    @ObservationIgnored private let updater: any SparkleUpdaterDriving
    @ObservationIgnored private let automaticChecks: AutomaticUpdateChecks
    @ObservationIgnored private var changeObservation: AnyObject?

    /// The real updater: Sparkle's standard controller, created without starting.
    convenience init(automaticChecks: AutomaticUpdateChecks) {
        self.init(automaticChecks: automaticChecks, updater: SparkleStandardUpdater())
    }

    /// The app's preference is applied before the updater starts, which is why the controller
    /// is created with `startingUpdater: false`: otherwise Sparkle asks on second launch whether
    /// to enable automatic checks, on a machine where the user may already have said no.
    init(automaticChecks: AutomaticUpdateChecks, updater: any SparkleUpdaterDriving) {
        self.automaticChecks = automaticChecks
        self.updater = updater
        self.canCheckForUpdates = updater.canCheckForUpdates
        self.lastUpdateCheckDate = updater.lastUpdateCheckDate

        AutomaticUpdateChecksPolicy.apply(preference: automaticChecks.isEnabled, to: self)
        updater.startUpdater()
        refresh()

        changeObservation = updater.observeChanges { [weak self] in
            let checker = self
            Self.onMainActor { checker?.refresh() }
        }
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
                updater.automaticallyChecksForUpdates = newValue
                automaticChecks.isEnabled = newValue
            }
        }
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    /// Mirrors the two values the surfaces read into Observation.
    private func refresh() {
        canCheckForUpdates = updater.canCheckForUpdates
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }

    /// Runs `work` on the main actor. Sparkle posts its changes on the main thread in practice,
    /// and then `work` runs before the callback returns, so the command is never shown enabled
    /// while a check is already running. A change posted from any other thread hops instead of
    /// trapping, as `MainActor.assumeIsolated` alone would.
    nonisolated static func onMainActor(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            Task { @MainActor in work() }
        }
    }
}

/// Sparkle's standard controller behind `SparkleUpdaterDriving`.
@MainActor
final class SparkleStandardUpdater: SparkleUpdaterDriving {
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil,
                                                          userDriverDelegate: nil)

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }
    var lastUpdateCheckDate: Date? { controller.updater.lastUpdateCheckDate }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func startUpdater() { controller.startUpdater() }
    func checkForUpdates() { controller.updater.checkForUpdates() }

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
        Self.observe(controller.updater, onChange: onChange)
    }

    /// Nonisolated so the KVO handlers carry no main-actor isolation of their own: they only
    /// forward to `onChange`, which decides how to reach the main actor.
    private nonisolated static func observe(_ updater: SPUUpdater,
                                            onChange: @escaping @Sendable () -> Void) -> AnyObject {
        let tokens = [
            updater.observe(\.canCheckForUpdates, options: [.new]) { _, _ in onChange() },
            updater.observe(\.lastUpdateCheckDate, options: [.new]) { _, _ in onChange() },
        ]
        return tokens as NSArray
    }
}
