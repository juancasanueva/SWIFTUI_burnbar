//
//  AppUpdating.swift
//  burnbar
//
//  The port every update surface speaks to. Sparkle is confined to one adapter in Data
//  (`SparkleUpdateChecker`); this is the only vocabulary that crosses out of it.
//

import Foundation
import Observation

/// Everything Burnbar's own surfaces ask of an updater, and nothing else.
///
/// Main-actor because the module compiles with main-actor default isolation and the concrete
/// updater is main-actor by construction. `AnyObject` because every surface must observe the
/// same instance. Refines `Observable` so a view holding `any AppUpdating` still re-renders:
/// Observation registers at the accessor, so tracking survives the existential.
@MainActor
protocol AppUpdating: AnyObject, Observable {
    /// Whether a check can run right now: false only while one is already in flight, never
    /// because automatic checking is off.
    var canCheckForUpdates: Bool { get }

    /// Whether the updater checks on its own. The app's persisted preference is the authority
    /// and is written at every launch.
    var automaticallyChecksForUpdates: Bool { get set }

    /// When the updater last completed a check, or nil if it never has.
    var lastUpdateCheckDate: Date? { get }

    /// Starts exactly one check.
    func checkForUpdates()
}
