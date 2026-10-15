//
//  AdviceEngine.swift
//  burnbar
//

import Foundation

/// Pace of one subscription's limits; nil rows are unknown.
nonisolated struct SubscriptionPace: Hashable, Sendable {
    let provider: Provider
    let fiveHour: Pace?
    let weekly: Pace?
}

/// The single advice chip in the bar.
nonisolated enum Advice: Hashable, Sendable {
    case keepUsing(Provider)
    case useNext(Provider)
    case useNow(Provider)
    case fiveHourOut(Provider, in: TimeInterval)
    case rest(Provider, for: TimeInterval)
    case spent

    var text: String {
        switch self {
        case .keepUsing(let p): "KEEP USING \(p.displayName)"
        case .useNext(let p): "USE \(p.displayName) NEXT"
        case .useNow(let p): "USE \(p.displayName) NOW"
        case .fiveHourOut(let p, let t): "\(p.displayName) 5-HOUR OUT IN \(Self.durationLabel(t))"
        case .rest(let p, let t): "\(p.displayName) REST \(Self.durationLabel(t))"
        case .spent: "SPENT"
        }
    }

    /// Higher is worse; a dismissed chip returns only when severity rises.
    var severity: Int {
        switch self {
        case .keepUsing: 0
        case .useNext, .useNow: 1
        case .fiveHourOut: 2
        case .rest: 3
        case .spent: 4
        }
    }

    /// "40M" under an hour (at least 1M), otherwise whole hours rounded, "8H".
    static func durationLabel(_ interval: TimeInterval) -> String {
        let minutes = interval / 60
        if minutes < 59.5 { return "\(max(1, Int(minutes.rounded())))M" }
        return "\(Int((minutes / 60).rounded()))H"
    }
}

/// Picks the advice chip. Rules, in order:
/// 1. Every sub blocked → SPENT. Blocked: 5-hour ≥ 90%, 5-hour full within 0.5 h, or weekly ≥ 99.5%.
/// 2. A candidate (unblocked, weekly banked ≥ 2%) whose weekly reset is within min(72 h, 15% of
///    its window) → USE X NOW (most banked first).
/// 3. Current sub blocked or over weekly pace → USE best candidate NEXT, else REST until the
///    blocking reset or until back on pace.
/// 4. Current 5-hour runs dry before its reset → X 5-HOUR OUT IN t.
/// 5. Another candidate banks ≥ 1.15× the current → USE it NEXT; otherwise KEEP USING current.
/// With no current sub, the most banked unblocked sub is treated as current.
nonisolated enum AdviceEngine {
    static let blockedFiveHour = 0.9
    static let blockedWithin: TimeInterval = 0.5 * 3600
    static let weeklyFull = 0.995
    static let minimumBanked = 0.02
    static let switchFactor = 1.15
    static let useNowHorizon: TimeInterval = 72 * 3600
    static let useNowShare = 0.15

    static func advise(_ subs: [SubscriptionPace], current: Provider?, now: Date) -> Advice {
        let open = subs.filter { !isBlocked($0, now: now) }
        guard !open.isEmpty else { return .spent }

        let candidates = open
            .filter { banked($0) >= minimumBanked }
            .sorted { banked($0) > banked($1) }

        if let soon = candidates.first(where: { isEndgame($0, now: now) }) {
            return .useNow(soon.provider)
        }

        guard let cur = subs.first(where: { $0.provider == current })
                ?? open.max(by: { banked($0) < banked($1) }) else { return .spent }
        let alternative = candidates.first { $0.provider != cur.provider }

        if isBlocked(cur, now: now) || cur.weekly?.isOver == true {
            if let alternative { return .useNext(alternative.provider) }
            return .rest(cur.provider, for: restInterval(cur, now: now))
        }

        if let five = cur.fiveHour, let dry = five.dryAt, dry < five.row.resetsAt {
            return .fiveHourOut(cur.provider, in: dry.timeIntervalSince(now).rounded())
        }

        if let alternative, banked(alternative) >= switchFactor * banked(cur) {
            return .useNext(alternative.provider)
        }
        return .keepUsing(cur.provider)
    }

    static func isBlocked(_ sub: SubscriptionPace, now: Date) -> Bool {
        if let five = sub.fiveHour {
            if five.percent >= blockedFiveHour { return true }
            if let dry = five.dryAt, dry.timeIntervalSince(now) <= blockedWithin { return true }
        }
        return (sub.weekly?.percent ?? 0) >= weeklyFull
    }

    /// Weekly banked share; unknown counts as 0 so it never wins a switch.
    private static func banked(_ sub: SubscriptionPace) -> Double { sub.weekly?.banked ?? 0 }

    private static func isEndgame(_ sub: SubscriptionPace, now: Date) -> Bool {
        guard let weekly = sub.weekly else { return false }
        let left = weekly.row.resetsAt.timeIntervalSince(now)
        return left <= min(useNowHorizon, useNowShare * weekly.row.windowDuration)
    }

    /// Longest wait among: a blocking 5-hour reset, a full weekly reset, getting back on weekly pace.
    private static func restInterval(_ sub: SubscriptionPace, now: Date) -> TimeInterval {
        var until = now
        if let five = sub.fiveHour, five.percent >= blockedFiveHour || (five.dryAt.map { $0.timeIntervalSince(now) <= blockedWithin } ?? false) {
            until = max(until, five.row.resetsAt)
        }
        if let weekly = sub.weekly {
            if weekly.percent >= weeklyFull { until = max(until, weekly.row.resetsAt) }
            if weekly.isOver, let back = weekly.backOnPaceAt { until = max(until, back) }
        }
        return until.timeIntervalSince(now).rounded()
    }
}
