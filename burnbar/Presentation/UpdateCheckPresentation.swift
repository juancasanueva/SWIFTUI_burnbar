//
//  UpdateCheckPresentation.swift
//  burnbar
//
//  The words an update surface may use about when the app last looked.
//

import Foundation

/// A pure function of two dates: `now` is injected so nothing reads the clock behind the caller.
nonisolated struct UpdateCheckPresentation: Sendable, Hashable {
    /// Words with no number in them: a placeholder date would state something untrue.
    static let neverChecked = "Never checked"

    let lastCheck: Date?
    let now: Date

    init(lastCheck: Date?, now: Date) {
        self.lastCheck = lastCheck
        self.now = now
    }

    var label: String {
        guard let lastCheck else { return Self.neverChecked }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Last checked \(formatter.localizedString(for: lastCheck, relativeTo: now))"
    }
}

/// What the setup screen's "Updates" group shows: plain values, so the view never sees the
/// updater (or Sparkle).
struct SetupUpdates: Hashable {
    /// "Burnbar <CFBundleShortVersionString> (<CFBundleVersion>)".
    let versionLine: String
    /// Whether "Check for Updates…" is live (`UpdateCommandEnablement`).
    let canCheck: Bool
    /// "Never checked" or "Last checked …" (`UpdateCheckPresentation`).
    let lastChecked: String

    init(versionLine: String, canCheck: Bool, lastChecked: String) {
        self.versionLine = versionLine
        self.canCheck = canCheck
        self.lastChecked = lastChecked
    }

    init(updater: any AppUpdating, bundleInfo: [String: Any], now: Date) {
        self.init(versionLine: Self.versionLine(bundleInfo: bundleInfo),
                  canCheck: UpdateCommandEnablement.isEnabled(canCheckForUpdates: updater.canCheckForUpdates),
                  lastChecked: UpdateCheckPresentation(lastCheck: updater.lastUpdateCheckDate, now: now).label)
    }

    /// Missing values are left out rather than invented.
    nonisolated static func versionLine(bundleInfo: [String: Any]) -> String {
        var line = "Burnbar"
        if let short = bundleInfo["CFBundleShortVersionString"] as? String, !short.isEmpty {
            line += " \(short)"
        }
        if let build = bundleInfo["CFBundleVersion"] as? String, !build.isEmpty {
            line += " (\(build))"
        }
        return line
    }
}
