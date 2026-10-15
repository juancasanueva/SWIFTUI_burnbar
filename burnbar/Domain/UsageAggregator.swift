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

    static func empty(_ provider: Provider) -> LaneUsage {
        LaneUsage(provider: provider, buckets: Array(repeating: 0, count: UsageAggregator.bucketCount),
                  heat: 0, split: .zero, byModel: [], turns: 0, sessions: 0, rate5m: 0, rate60m: 0)
    }
}

nonisolated struct UsageSummary: Hashable, Sendable {
    let bucketStarts: [Date]
    let lanes: [Provider: LaneUsage]

    func lane(_ provider: Provider) -> LaneUsage { lanes[provider] ?? .empty(provider) }

    var totalHeat: Int { lanes.values.reduce(0) { $0 + $1.heat } }
    var turns: Int { lanes.values.reduce(0) { $0 + $1.turns } }
    var sessions: Int { lanes.values.reduce(0) { $0 + $1.sessions } }
    /// Hottest bucket across lanes, for a shared heat scale.
    var peakBucketHeat: Int { lanes.values.map(\.peakBucketHeat).max() ?? 0 }
}

/// Buckets usage events into the bar's heat strip and headline numbers.
///
/// - 12 buckets × 30 min aligned to the wall-clock grid; the last bucket contains `now`.
/// - Headline totals cover the exact trailing 360 min, so they can include burn older than bucket 0.
/// - Events after `now` are ignored.
nonisolated enum UsageAggregator {
    static let windowDuration: TimeInterval = 360 * 60
    static let bucketCount = 12
    static let bucketDuration: TimeInterval = 30 * 60

    static func bucketStarts(now: Date) -> [Date] {
        let t = now.timeIntervalSince1970
        let last = (t / bucketDuration).rounded(.down) * bucketDuration
        return (0..<bucketCount).map { i in
            Date(timeIntervalSince1970: last - Double(bucketCount - 1 - i) * bucketDuration)
        }
    }

    static func summarize(_ events: [UsageEvent], now: Date) -> UsageSummary {
        let starts = bucketStarts(now: now)
        let windowStart = now.addingTimeInterval(-windowDuration)
        let inWindow = events.filter { $0.timestamp > windowStart && $0.timestamp <= now }
        let grouped = Dictionary(grouping: inWindow, by: \.provider)
        let lanes = Dictionary(uniqueKeysWithValues: grouped.map { provider, events in
            (provider, lane(events, provider: provider, starts: starts, now: now))
        })
        return UsageSummary(bucketStarts: starts, lanes: lanes)
    }

    private static func lane(_ events: [UsageEvent], provider: Provider, starts: [Date], now: Date) -> LaneUsage {
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
