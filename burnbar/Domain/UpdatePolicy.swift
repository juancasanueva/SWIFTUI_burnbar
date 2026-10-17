//
//  UpdatePolicy.swift
//  burnbar
//
//  What the app writes to the updater at launch, and when "Check for Updates…" is live. The
//  decisions live here; the effects live in the Sparkle adapter.
//

/// The app's own persisted preference decides whether Burnbar checks on its own: neither a
/// bundled value nor a value Sparkle persisted behind the app's back.
@MainActor
enum AutomaticUpdateChecksPolicy {
    /// Writes the preference exactly once, unconditionally. "Only write when it differs" would
    /// leave a framework-persisted value inspected instead of overwritten.
    static func apply(preference: Bool, to updater: any AppUpdating) {
        updater.automaticallyChecksForUpdates = preference
    }
}

/// Whether the explicit "Check for Updates…" command is live. An explicit action is its own
/// consent, so the only reason to refuse is that a check cannot run (one is in flight).
nonisolated enum UpdateCommandEnablement {
    static func isEnabled(canCheckForUpdates: Bool) -> Bool {
        canCheckForUpdates
    }
}
