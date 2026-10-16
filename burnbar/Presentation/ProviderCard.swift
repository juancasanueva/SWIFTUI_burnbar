//
//  ProviderCard.swift
//  burnbar
//
//  Plain view state for the cockpit panel: everything one provider card and the header show,
//  mapped from `ProviderState` / `UsageViewState` so the views stay presentational and testable.
//

import Foundation

/// One point of a burndown series: used share (0...1) at an instant.
nonisolated struct BurndownPoint: Hashable, Sendable {
    let t: Date
    let percent: Double
}

/// The burndown of a provider's weekly (or longest) window.
nonisolated struct Burndown: Hashable, Sendable {
    let label: String
    let pace: Pace
    let windowStart: Date
    let resetsAt: Date
    /// Window start at 0%, the recorded samples of this window, then the current share. A
    /// restarted window (projected reset) has no samples of its own: just its 0% points.
    let actual: [BurndownPoint]
    /// A straight burn from 0% at the window start to 100% at the reset.
    let ideal: [BurndownPoint]
    /// From now along the fitted rate: to the reset, or to 100% when it runs dry first.
    /// Nil without a rate.
    let projected: [BurndownPoint]?
    /// E.g. "Weekly (7-day) burndown: 50% used, 50% of the window elapsed, projected 80% at the reset".
    let accessibilitySummary: String

    var isProjectedReset: Bool { pace.isProjectedReset }

    init(label: String, pace: Pace, samples: [LimitSample], now: Date) {
        let row = pace.row
        let start = row.resetsAt.addingTimeInterval(-row.windowDuration)
        self.label = label
        self.pace = pace
        self.windowStart = start
        self.resetsAt = row.resetsAt

        // Samples of this window only: by time, and by the reset reported when sampled. After a
        // passed reset any reading still reported belongs to the finished window, so a restarted
        // window keeps none.
        // Sorted by time, ties kept in their original order (explicit index tie-break, not
        // relying on sort stability), so for one instant the last-given sample wins below.
        let recorded = pace.isProjectedReset ? [] : samples
            .filter { $0.t > start && $0.t < now && $0.belongs(toWindowEndingAt: row.resetsAt) }
            .enumerated()
            .sorted { ($0.element.t, $0.offset) < ($1.element.t, $1.offset) }
            .map { BurndownPoint(t: $0.element.t, percent: min(max($0.element.percent, 0), 1)) }
        actual = Self.uniqueTimes([BurndownPoint(t: start, percent: 0)] + recorded + [BurndownPoint(t: now, percent: pace.percent)])
        ideal = [BurndownPoint(t: start, percent: 0), BurndownPoint(t: row.resetsAt, percent: 1)]

        var summary = "\(label) burndown: \(CockpitFormat.percent(pace.percent)) used, "
            + "\(CockpitFormat.percent(pace.elapsed)) of the window elapsed"
        if let projectedShare = pace.projected {
            let current = BurndownPoint(t: now, percent: pace.percent)
            if let dry = pace.dryAt, dry < row.resetsAt {
                projected = Self.uniqueTimes([current, BurndownPoint(t: dry, percent: 1)])
                summary += ", projected to run out in \(CockpitFormat.duration(dry.timeIntervalSince(now)))"
            } else {
                projected = [current, BurndownPoint(t: row.resetsAt, percent: projectedShare)]
                summary += ", projected \(CockpitFormat.percent(projectedShare)) at the reset"
            }
        } else {
            projected = nil
            summary += ", no projection yet"
        }
        accessibilitySummary = summary
    }

    /// One point per instant (the last one wins), so every chart point has a distinct x.
    private static func uniqueTimes(_ points: [BurndownPoint]) -> [BurndownPoint] {
        var unique: [BurndownPoint] = []
        for point in points {
            if unique.last?.t == point.t { unique.removeLast() }
            unique.append(point)
        }
        return unique
    }
}

/// One limit row of a card: label, used share, reset and gauge.
nonisolated struct LimitLine: Hashable, Sendable, Identifiable {
    let label: String
    /// Nil when the row is unknown.
    let percent: Double?
    /// Share of the window elapsed: where an even burn would be now. Nil when unknown.
    let elapsed: Double?
    let gauge: GaugeLevel?
    let resetsAt: Date
    let isProjectedReset: Bool
    /// Time until the reset, e.g. "2h 30m".
    let resetIn: String

    var id: String { label }

    var percentText: String { percent.map(CockpitFormat.percent) ?? "—" }

    /// E.g. "resets in 2h 30m"; "~resets in 5d 0h" when the reset is assumed.
    var resetText: String { (isProjectedReset ? "~" : "") + "resets in \(resetIn)" }

    var accessibilityLabel: String {
        let used = percent.map { "\(CockpitFormat.percent($0)) used" } ?? "usage unknown"
        return "\(label), \(used), \(isProjectedReset ? "assumed reset" : "resets") in \(resetIn)"
    }

    init(_ state: LimitRowState, now: Date) {
        let pace = state.pace
        label = state.row.label
        percent = pace?.percent
        elapsed = pace?.elapsed
        gauge = pace?.gauge
        resetsAt = state.row.resetsAt
        isProjectedReset = pace?.isProjectedReset ?? false
        resetIn = CockpitFormat.duration(state.row.resetsAt.timeIntervalSince(now))
    }
}

/// Display preferences applied when mapping provider state to cards.
nonisolated struct CardOptions: Hashable, Sendable {
    /// Cards name the signed-in account.
    var showsAccountName = true
    /// Cards list 5-hour rows; off, only a 5-hour row about to run out is listed.
    var showsFiveHourWindows = true

    func shows(_ limit: LimitRowState) -> Bool {
        guard !showsFiveHourWindows, limit.row.windowDuration == 5 * 3600 else { return true }
        return limit.pace.map(AdviceEngine.isFiveHourRunningOut) ?? false
    }
}

/// Everything one provider card shows.
nonisolated struct ProviderCard: Hashable, Sendable, Identifiable {
    let provider: Provider
    /// Nil when unknown or when account names are hidden.
    let accountLabel: String?
    /// Verdict of the burndown row; nil when no limit is known.
    let verdict: Verdict?
    /// One line of what to do now, from the pace rules.
    let instruction: String
    /// The limit rows the options show.
    let lines: [LimitLine]
    let burndown: Burndown?
    /// Spent share, name and reset of the burndown row; nil when no limit is known.
    let budget: BudgetSummary?
    /// The coloured status line under the title, e.g. "BANKED 51%".
    let statusLine: CardStatus
    /// How fast to spend from here, e.g. "Spend up to 1.5% an hour and it lasts to the reset".
    let spendAdvice: String?
    /// Heat per strip bucket, oldest first, for the burn histogram.
    let buckets: [Int]
    let rate5m: Double
    let rate60m: Double
    let split: TokenSplit
    /// The three hottest models.
    let topModels: [ModelUsage]
    let tokens: Int
    let turns: Int
    let sessions: Int
    let status: String?
    let isStale: Bool
    let hasError: Bool

    var id: Provider { provider }
    var title: String { provider.title }
    var tokensText: String { CockpitFormat.tokens(tokens) }
    var rate5mText: String { CockpitFormat.rate(rate5m) }
    var rate60mText: String { CockpitFormat.rate(rate60m) }

    init(state: ProviderState, now: Date, options: CardOptions = CardOptions()) {
        provider = state.provider
        accountLabel = options.showsAccountName ? state.account?.label : nil
        lines = state.limits.filter(options.shows).map { LimitLine($0, now: now) }

        let headline = Self.headline(state.limits)
        burndown = headline.map { row in
            Burndown(label: row.row.label, pace: row.pace!, samples: state.samples[row.row.label] ?? [], now: now)
        }
        verdict = headline?.pace?.verdict
        instruction = Self.instruction(headline: headline?.pace, fiveHour: state.fiveHour, status: state.status, now: now)
        budget = headline?.pace.map { BudgetSummary(pace: $0, now: now) }
        statusLine = CardStatus(headline: headline?.pace, fiveHour: state.fiveHour, status: state.status,
                                hasError: state.hasError, now: now)
        spendAdvice = headline?.pace.map(Self.spendAdvice)

        let lane = state.lane
        buckets = lane.buckets
        rate5m = lane.rate5m
        rate60m = lane.rate60m
        split = lane.split
        topModels = Array(lane.byModel.prefix(3))
        tokens = lane.heat
        turns = lane.turns
        sessions = lane.sessions
        status = state.status
        isStale = state.isStale
        hasError = state.hasError
    }

    /// The weekly row, else the longest-window row, among rows with a known pace.
    private static func headline(_ limits: [LimitRowState]) -> LimitRowState? {
        let known = limits.filter { $0.pace != nil }
        return known.first { $0.row.windowDuration == 7 * 24 * 3600 }
            ?? known.max { $0.row.windowDuration < $1.row.windowDuration }
    }

    /// In order: spent → back at the reset; 5-hour ≥ 90% → come back at its reset; over pace →
    /// come back when back on pace (else at the reset); ≥ 2% banked → banked x%; else on pace.
    static func instruction(headline: Pace?, fiveHour: Pace?, status: String?, now: Date) -> String {
        guard let pace = headline else { return status ?? "Limits unknown" }
        if pace.percent >= AdviceEngine.weeklyFull { return "Spent — back at the reset" }
        if let five = fiveHour, five.percent >= AdviceEngine.blockedFiveHour {
            return "5-hour nearly out — come back in \(CockpitFormat.duration(five.row.resetsAt.timeIntervalSince(now)))"
        }
        if pace.isOver {
            guard let back = pace.backOnPaceAt, back < pace.row.resetsAt else { return "Over pace — back at the reset" }
            return "Over pace — come back in \(CockpitFormat.duration(back.timeIntervalSince(now)))"
        }
        if pace.banked >= AdviceEngine.minimumBanked {
            return "Banked \(CockpitFormat.percent(pace.banked)) — room to burn"
        }
        return "On pace — keep going"
    }
}

/// The panel header: totals over the trailing window across every lane.
nonisolated struct CockpitHeader: Hashable, Sendable {
    let tokens: Int
    let turns: Int
    let sessions: Int
    let updatedAt: Date?
    /// The trailing window the totals cover.
    let window: TimeInterval

    var tokensText: String { CockpitFormat.tokens(tokens) }
    /// E.g. "6 h", "1 d".
    var windowLabel: String { CockpitFormat.window(window) }

    init(state: UsageViewState) {
        tokens = state.summary.totalHeat
        turns = state.summary.turns
        sessions = state.summary.sessions
        updatedAt = state.updatedAt
        window = state.summary.window
    }
}

/// Deterministic, locale-free short formats for the cockpit.
nonisolated enum CockpitFormat {
    /// "0m" when passed, "42m" under an hour (at least 1m), "3h 05m" under a day, else "2d 4h".
    static func duration(_ interval: TimeInterval) -> String {
        guard interval > 0 else { return "0m" }
        let minutes = Int((interval / 60).rounded())
        if minutes < 60 { return "\(max(1, minutes))m" }
        if minutes < 24 * 60 { return "\(minutes / 60)h " + String(format: "%02dm", minutes % 60) }
        return "\(minutes / (24 * 60))d \((minutes % (24 * 60)) / 60)h"
    }

    /// Whole days from a day up, else whole hours: "1 d", "12 h", "1 h".
    static func window(_ interval: TimeInterval) -> String {
        let hours = Int((interval / 3600).rounded())
        return hours >= 24 && hours % 24 == 0 ? "\(hours / 24) d" : "\(hours) h"
    }

    /// "999", "1.5K", "2.5M".
    static func tokens(_ count: Int) -> String {
        switch count {
        case ..<1000: "\(count)"
        case ..<1_000_000: String(format: "%.1fK", Double(count) / 1000)
        default: String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }

    /// Tokens per minute, e.g. "1.5K/min".
    static func rate(_ perMinute: Double) -> String {
        "\(tokens(Int(perMinute.rounded())))/min"
    }

    /// A share as a whole percent, e.g. 0.42 → "42%".
    static func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}

/// Pace verdict colours: green, yellow, orange, red.
nonisolated extension Verdict {
    var tint: RGBHex {
        switch self {
        case .onTrack: RGBHex(0x34C759)
        case .atPace: RGBHex(0xFFCC00)
        case .over: RGBHex(0xFF9500)
        case .wayOver: LanePalette.error
        }
    }
}

/// Gauge colours: green, yellow from 75%, red from 90%.
nonisolated extension GaugeLevel {
    var tint: RGBHex {
        switch self {
        case .green: RGBHex(0x34C759)
        case .yellow: RGBHex(0xFFCC00)
        case .red: LanePalette.error
        }
    }
}
