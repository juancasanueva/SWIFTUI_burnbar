//
//  UsageCollector.swift
//  burnbar
//

import Foundation

/// Reads one provider's local transcripts into deduplicated Domain events.
///
/// Implementations are expected to be incremental: repeated calls only read what changed
/// and return the current events of the trailing window.
nonisolated protocol UsageCollector: Sendable {
    func events(now: Date) async -> [UsageEvent]
}
