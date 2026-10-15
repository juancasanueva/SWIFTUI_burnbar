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
}
