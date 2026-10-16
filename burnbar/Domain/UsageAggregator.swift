//
//  UsageAggregator.swift
//  burnbar
//

import Foundation

nonisolated struct ModelUsage: Hashable, Sendable {
    let model: String
    let split: TokenSplit
}

/// Burn of one provider over the trailing window.
nonisolated struct LaneUsage: Hashable, Sendable {
    let provider: Provider
    /// Heat per grid bucket, oldest first.
    let buckets: [Int]
    /// Heat over the exact trailing window (may include time before the first bucket).
    let heat: Int
    let split: TokenSplit
    /// Hottest model first.
    let byModel: [ModelUsage]
    let turns: Int
    let sessions: Int
    /// Heat per minute over the last 5 and 60 minutes.
    let rate5m: Double
    let rate60m: Double

    var peakBucketHeat: Int { buckets.max() ?? 0 }
    /// Index of the hottest bucket; nil when the lane is idle.
    var peakBucketIndex: Int? {
        guard peakBucketHeat > 0 else { return nil }
        return buckets.firstIndex(of: peakBucketHeat)
    }

    static func empty(_ provider: Provider, cells: Int = UsageAggregator.bucketCount) -> LaneUsage {
        LaneUsage(provider: provider, buckets: Array(repeating: 0, count: cells),
                  heat: 0, split: .zero, byModel: [], turns: 0, sessions: 0, rate5m: 0, rate60m: 0)
    }
}

nonisolated struct UsageSummary: Hashable, Sendable {
    let bucketStarts: [Date]
    let lanes: [Provider: LaneUsage]
    /// The trailing window the totals cover.
    var window: TimeInterval = UsageAggregator.windowDuration

    /// An idle lane has as many cells as the grid (the standard count before any grid is known).
    func lane(_ provider: Provider) -> LaneUsage {
        lanes[provider] ?? .empty(provider, cells: bucketStarts.isEmpty ? UsageAggregator.bucketCount : bucketStarts.count)
    }

    var totalHeat: Int { lanes.values.reduce(0) { $0 + $1.heat } }
    var turns: Int { lanes.values.reduce(0) { $0 + $1.turns } }
    var sessions: Int { lanes.values.reduce(0) { $0 + $1.sessions } }
    /// Hottest bucket across lanes, for a shared heat scale.
    var peakBucketHeat: Int { lanes.values.map(\.peakBucketHeat).max() ?? 0 }
}

/// The heat strip's shape: a trailing window split into equal cells.
nonisolated struct StripGrid: Hashable, Sendable {
    let window: TimeInterval
    let cells: Int

    var bucketDuration: TimeInterval { window / Double(cells) }

    /// 12 cells × 30 min over 6 hours.
    static let standard = StripGrid(window: 360 * 60, cells: 12)
}

/// Buckets usage events into the bar's heat strip and headline numbers.
///
/// - `grid.cells` buckets of `grid.bucketDuration` aligned to the wall-clock grid (multiples of
///   the bucket length since the epoch); the last bucket contains `now`. Standard: 12 × 30 min.
/// - Headline totals cover the exact trailing `grid.window`, so they can include burn older than bucket 0.
/// - Events after `now` are ignored.
nonisolated enum UsageAggregator {
    static let windowDuration: TimeInterval = StripGrid.standard.window
    static let bucketCount = StripGrid.standard.cells
    static let bucketDuration: TimeInterval = StripGrid.standard.bucketDuration

    static func bucketStarts(now: Date, grid: StripGrid = .standard) -> [Date] {
        let duration = grid.bucketDuration
        let last = (now.timeIntervalSince1970 / duration).rounded(.down) * duration
        return (0..<grid.cells).map { i in
            Date(timeIntervalSince1970: last - Double(grid.cells - 1 - i) * duration)
        }
    }

    static func summarize(_ events: [UsageEvent], now: Date, grid: StripGrid = .standard) -> UsageSummary {
        let starts = bucketStarts(now: now, grid: grid)
        let windowStart = now.addingTimeInterval(-grid.window)
        let inWindow = events.filter { $0.timestamp > windowStart && $0.timestamp <= now }
        let grouped = Dictionary(grouping: inWindow, by: \.provider)
        let lanes = Dictionary(uniqueKeysWithValues: grouped.map { provider, events in
            (provider, lane(events, provider: provider, starts: starts, bucketDuration: grid.bucketDuration, now: now))
        })
        return UsageSummary(bucketStarts: starts, lanes: lanes, window: grid.window)
    }

    private static func lane(
        _ events: [UsageEvent], provider: Provider, starts: [Date], bucketDuration: TimeInterval, now: Date
    ) -> LaneUsage {
        let bucketCount = starts.count
        var buckets = Array(repeating: 0, count: bucketCount)
        var split = TokenSplit.zero
        var models: [String: TokenSplit] = [:]
        var sessions = Set<String>()
        var last5 = 0, last60 = 0
        let first = starts[0]

        for event in events {
            let heat = event.split.heat
            split += event.split
            models[event.model, default: .zero] += event.split
            if let id = event.sessionID { sessions.insert(id) }

            let offset = event.timestamp.timeIntervalSince(first)
            if offset >= 0 { buckets[min(bucketCount - 1, Int(offset / bucketDuration))] += heat }

            let age = now.timeIntervalSince(event.timestamp)
            if age < 5 * 60 { last5 += heat }
            if age < 60 * 60 { last60 += heat }
        }

        let byModel = models
            .map { ModelUsage(model: $0.key, split: $0.value) }
            .sorted { ($0.split.heat, $1.model) > ($1.split.heat, $0.model) }

        return LaneUsage(provider: provider, buckets: buckets, heat: split.heat, split: split, byModel: byModel,
                         turns: events.count, sessions: sessions.count,
                         rate5m: Double(last5) / 5, rate60m: Double(last60) / 60)
    }
}
