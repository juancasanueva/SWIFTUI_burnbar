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
