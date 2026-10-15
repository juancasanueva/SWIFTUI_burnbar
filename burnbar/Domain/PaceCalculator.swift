//
//  PaceCalculator.swift
//  burnbar
//

import Foundation

/// Pace of one limit row at `now`. Percentages are shares in 0...1.
nonisolated struct Pace: Hashable, Sendable {
    let row: LimitRow
    /// Share of the window already elapsed, e = (L − (r − now)) / L.
    let elapsed: Double
    /// p / e; nil while e < 1%.
    let ratio: Double?
    let hoursLeft: Double
    /// Share per hour that would land exactly at 100% on reset: (1 − p) / hoursLeft.
    let allowancePerHour: Double
    /// Least-squares slope of recent samples, share per hour; nil without enough samples.
    let ratePerHour: Double?
    /// p + rate · hoursLeft.
    let projected: Double?
    /// now + (1 − p) / rate, when burning.
    let dryAt: Date?
    /// r − L(1 − p): when elapsed catches up with usage; nil when already on pace.
    let backOnPaceAt: Date?
    /// Windows ≥ 36 h: share spendable today, (1 − p) · min(1, 24 / hoursLeft).
    let todayCeiling: Double?

    /// Used share clamped to 0...1, the same value every derived field is computed from.
    var percent: Double { min(max(row.percent, 0), 1) }
    /// Share saved versus a linear burn, e − p.
    var banked: Double { elapsed - percent }
    /// More than 1% behind and ratio > 1.05.
    var isOver: Bool { percent - elapsed > 0.01 && (ratio ?? 0) > 1.05 }

    var verdict: Verdict { Verdict(ratio: ratio) }
    var stage: Stage { Stage(ratio: ratio, percent: percent) }
    var gauge: GaugeLevel { GaugeLevel(percent: percent) }
}

nonisolated enum PaceCalculator {
    static let minimumElapsed = 0.01
    static let rateLookback: TimeInterval = 2 * 3600
    static let rateLookbackShare = 0.1
    static let minimumSampleSpan: TimeInterval = 10 * 60
    static let giftDrop = 0.03
    static let dailyCeilingWindow: TimeInterval = 36 * 3600

    /// Pace for `row`, or nil (unknown) when its reset already passed.
    ///
    /// Rate samples: only those of the current window (same reset), after the last gift
    /// (a drop of ≥ 3%, which rebases the fit), within min(2 h, 10% of the window) of `now`,
    /// spanning ≥ 10 min. Negative slopes clamp to 0.
    static func pace(for row: LimitRow, samples: [LimitSample], now: Date) -> Pace? {
        let left = row.resetsAt.timeIntervalSince(now)
        let window = row.windowDuration
        guard left > 0, window > 0 else { return nil }

        let p = min(max(row.percent, 0), 1)
        let e = min(max((window - left) / window, 0), 1)
        let hoursLeft = left / 3600
        let rate = ratePerHour(samples, row: row, now: now)
        let burning = rate.map { $0 > 1e-9 } ?? false
        let backOnPace = row.resetsAt.addingTimeInterval(-window * (1 - p))

        return Pace(
            row: row,
            elapsed: e,
            ratio: e >= minimumElapsed ? p / e : nil,
            hoursLeft: hoursLeft,
            allowancePerHour: (1 - p) / hoursLeft,
            ratePerHour: rate,
            projected: rate.map { p + $0 * hoursLeft },
            dryAt: burning ? now.addingTimeInterval((1 - p) / rate! * 3600) : nil,
            backOnPaceAt: backOnPace > now ? backOnPace : nil,
            todayCeiling: window >= dailyCeilingWindow ? (1 - p) * min(1, 24 / hoursLeft) : nil
        )
    }

    /// Limits fetched longer ago than max(15 min, 3 refreshes) are stale.
    static func isStale(fetchedAt: Date, refreshInterval: TimeInterval, now: Date) -> Bool {
        now.timeIntervalSince(fetchedAt) > max(900, 3 * refreshInterval)
    }

    private static func ratePerHour(_ samples: [LimitSample], row: LimitRow, now: Date) -> Double? {
        let windowStart = row.resetsAt.addingTimeInterval(-row.windowDuration)
        var current = samples
            .filter { $0.t >= windowStart && $0.t <= now }
            .sorted { $0.t < $1.t }
        if let gift = current.indices.dropFirst().last(where: { current[$0 - 1].percent - current[$0].percent >= giftDrop }) {
            current.removeFirst(gift)
        }
        let cutoff = now.addingTimeInterval(-min(rateLookback, rateLookbackShare * row.windowDuration))
        let recent = current.filter { $0.t >= cutoff }
        guard let first = recent.first, let last = recent.last,
              last.t.timeIntervalSince(first.t) >= minimumSampleSpan else { return nil }

        let xs = recent.map { $0.t.timeIntervalSince(first.t) / 3600 }
        let ys = recent.map(\.percent)
        let mx = xs.reduce(0, +) / Double(xs.count)
        let my = ys.reduce(0, +) / Double(ys.count)
        let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        return max(0, sxy / sxx)
    }
}
