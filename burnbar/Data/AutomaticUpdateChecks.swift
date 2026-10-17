//
//  AutomaticUpdateChecks.swift
//  burnbar
//
//  Whether Burnbar may look for updates on its own, over an injected `UserDefaults`.
//

import Foundation

/// A missing key reads `false`: an update check is network egress, and "we never asked" must
/// not be storable as "they said yes". This value, not Sparkle's bundled or persisted one, is
/// the authority; the launch wiring writes it to the updater every time.
nonisolated struct AutomaticUpdateChecks {
    static let key = "updates.automaticChecksEnabled"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// `nonmutating set`: the storage is the defaults domain, not this value.
    var isEnabled: Bool {
        get { defaults.bool(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
