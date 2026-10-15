//
//  LimitsSource.swift
//  burnbar
//

import Foundation

/// Supplies one provider's current plan limits, e.g. from local rollout files or an API.
///
/// Returns nil when no limits are known yet; callers keep showing the last snapshot and
/// judge staleness from `LimitSnapshot.measuredAt`.
nonisolated protocol LimitsSource: Sendable {
    func limits(now: Date) async -> LimitSnapshot?
    /// - Parameter force: Skip any refresh-interval cache, e.g. when the panel opens.
    func limits(now: Date, force: Bool) async -> LimitSnapshot?
}

extension LimitsSource {
    /// Sources without a cache have nothing to skip.
    func limits(now: Date, force: Bool) async -> LimitSnapshot? {
        await limits(now: now)
    }
}
