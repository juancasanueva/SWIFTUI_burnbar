//
//  ProviderCardTests.swift
//  burnbarTests
//

import Foundation
import Testing
@testable import burnbar

struct ProviderCardTests {
    private let weeklyLabel = "Weekly (7-day)"
    private let fiveHourLabel = "Session (5-hour)"

    /// A provider state with paces computed like the store does.
    private func state(
        _ provider: Provider = .claude,
        rows: [LimitRow],
        samples: [String: [LimitSample]] = [:],
        lane: LaneUsage? = nil,
        status: String? = nil,
        isStale: Bool = false,
        hasError: Bool = false,
        account: AccountInfo? = AccountInfo(email: "dev@example.com")
    ) -> ProviderState {
        let limits = rows.map { row in
            let pace = PaceCalculator.pace(for: row, samples: samples[row.label] ?? [], now: now)
            return LimitRowState(row: pace?.row ?? row, pace: pace)
        }
        return ProviderState(provider: provider, lane: lane ?? .empty(provider), limits: limits,
                             measuredAt: now, status: status, isStale: isStale, hasError: hasError,
                             account: account, samples: samples)
    }

    private func card(_ state: ProviderState) -> ProviderCard {
        ProviderCard(state: state, now: now)
    }

    // MARK: Instruction

    @Test func bankedWeekSaysHowMuchIsBanked() {
        let c = card(state(rows: [row(fiveHourLabel, percent: 0.2, elapsed: 0.4, window: fiveHours),
                                  row(weeklyLabel, percent: 0.3, elapsed: 0.5)]))
        #expect(c.verdict == .onTrack)
        #expect(c.instruction == "Banked 20% — room to burn")
    }

    @Test func onPaceWhenNothingMeaningfulIsBanked() {
        let c = card(state(rows: [row(weeklyLabel, percent: 0.49, elapsed: 0.5)]))
        #expect(c.verdict == .atPace)
        #expect(c.instruction == "On pace — keep going")
    }

    @Test func overPaceSaysWhenToComeBack() {
        // 60% used, 50% elapsed: back on pace when elapsed reaches 60%, i.e. 0.1 week from now.
        let c = card(state(rows: [row(weeklyLabel, percent: 0.6, elapsed: 0.5)]))
        #expect(c.verdict == .over)
        #expect(c.instruction == "Over pace — come back in \(CockpitFormat.duration(0.1 * week))")
    }

    @Test func spentWeekIsBackAtTheReset() {
        let c = card(state(rows: [row(weeklyLabel, percent: 1.0, elapsed: 0.9)]))
        #expect(c.instruction == "Spent — back at the reset")
    }

    @Test func nearlySpentFiveHourSaysWhenToComeBack() {
        let c = card(state(rows: [row(fiveHourLabel, percent: 0.95, elapsed: 0.5, window: fiveHours),
                                  row(weeklyLabel, percent: 0.3, elapsed: 0.5)]))
        #expect(c.instruction == "5-hour nearly out — come back in \(CockpitFormat.duration(2.5 * hour))")
    }

    @Test func unknownLimitsSayWhy() {
        #expect(card(state(rows: [])).instruction == "Limits unknown")
        #expect(card(state(rows: [], status: "Claude limits unreachable")).instruction == "Claude limits unreachable")
        #expect(card(state(rows: [])).verdict == nil)
    }

    // MARK: Verdict and gauge colours

    @Test(arguments: [
        (Verdict.onTrack, RGBHex(0x34C759)),
        (.atPace, RGBHex(0xFFCC00)),
        (.over, RGBHex(0xFF9500)),
        (.wayOver, RGBHex(0xFF3B30)),
    ])
    func verdictColours(verdict: Verdict, colour: RGBHex) {
        #expect(verdict.tint == colour)
    }

    @Test(arguments: [
        (GaugeLevel.green, RGBHex(0x34C759)),
        (.yellow, RGBHex(0xFFCC00)),
        (.red, RGBHex(0xFF3B30)),
    ])
    func gaugeColours(level: GaugeLevel, colour: RGBHex) {
        #expect(level.tint == colour)
    }

    // MARK: Limit lines

    @Test func limitLinesShowPercentResetAndGauge() throws {
        let c = card(state(rows: [row(fiveHourLabel, percent: 0.8, elapsed: 0.5, window: fiveHours),
                                  row(weeklyLabel, percent: 0.3, elapsed: 0.5)]))
        #expect(c.lines.map(\.label) == [fiveHourLabel, weeklyLabel])
        let five = c.lines[0]
        #expect(five.percent == 0.8)
        #expect(five.percentText == "80%")
        #expect(five.gauge == .yellow)
        #expect(five.resetText == "resets in \(CockpitFormat.duration(2.5 * hour))")
        #expect(five.accessibilityLabel == "\(fiveHourLabel), 80% used, resets in \(CockpitFormat.duration(2.5 * hour))")
    }

    @Test func aProjectedResetIsMarkedWithATilde() throws {
        let passed = LimitRow(label: weeklyLabel, percent: 0.12, resetsAt: now.addingTimeInterval(-2 * 24 * hour), windowDuration: week)
        let c = card(state(.codex, rows: [passed]))
        let line = try #require(c.lines.first)
        #expect(line.isProjectedReset)
        #expect(line.percentText == "0%")
        #expect(line.resetText == "~resets in 5d 0h")
        #expect(line.accessibilityLabel.contains("assumed reset"))
    }

    // MARK: Burndown

    @Test func burndownUsesTheWeeklyRowWithIdealAndProjectedLines() throws {
        let weekly = row(weeklyLabel, percent: 0.5, elapsed: 0.5)
        let start = weekly.resetsAt.addingTimeInterval(-week)
        // 6% per hour over the last hour.
        let samples = [weeklyLabel: [sample(at: -hour, 0.44), sample(at: -30 * minute, 0.47)]]
        let c = card(state(rows: [row(fiveHourLabel, percent: 0.2, elapsed: 0.4, window: fiveHours), weekly], samples: samples))
        let chart = try #require(c.burndown)
        #expect(chart.label == weeklyLabel)
        #expect(chart.windowStart == start)
        #expect(chart.resetsAt == weekly.resetsAt)
        #expect(chart.ideal == [BurndownPoint(t: start, percent: 0), BurndownPoint(t: weekly.resetsAt, percent: 1)])
        #expect(chart.actual == [BurndownPoint(t: start, percent: 0),
                                 BurndownPoint(t: now.addingTimeInterval(-hour), percent: 0.44),
                                 BurndownPoint(t: now.addingTimeInterval(-30 * minute), percent: 0.47),
                                 BurndownPoint(t: now, percent: 0.5)])
        // 0.5 left at 0.06/h → dry in 8.33 h, well before the reset: the projection stops at 100%.
        let projected = try #require(chart.projected)
        #expect(projected.count == 2)
        #expect(projected[0] == BurndownPoint(t: now, percent: 0.5))
        #expect(projected[1].percent == 1)
        #expect(abs(projected[1].t.timeIntervalSince(now) - 0.5 / 0.06 * hour) < 1)
        #expect(chart.accessibilitySummary.hasPrefix("\(weeklyLabel) burndown: 50% used, 50% of the window elapsed"))
    }

    @Test func projectionEndsAtTheResetWhenItDoesNotRunDry() throws {
        let weekly = row(weeklyLabel, percent: 0.2, elapsed: 0.5)
        // 0.5% per hour: 0.2 + 0.005 · 84 h = 62% at the reset.
        let samples = [weeklyLabel: [sample(at: -hour, 0.195), sample(at: 0, 0.2)]]
        let c = card(state(rows: [weekly], samples: samples))
        let projected = try #require(c.burndown?.projected)
        #expect(projected.last?.t == weekly.resetsAt)
        let pace = try #require(c.burndown?.pace)
        #expect(abs(projected.last!.percent - pace.projected!) < 1e-9)
    }

    @Test func noProjectionWithoutARate() throws {
        let c = card(state(rows: [row(weeklyLabel, percent: 0.2, elapsed: 0.5)]))
        #expect(c.burndown?.projected == nil)
        #expect(c.burndown?.actual == [BurndownPoint(t: now.addingTimeInterval(-0.5 * week), percent: 0),
                                       BurndownPoint(t: now, percent: 0.2)])
    }

    @Test func burndownFallsBackToTheLongestWindowAndDropsOldSamples() throws {
        let daily = row("Daily (1-day)", percent: 0.3, elapsed: 0.5, window: 24 * hour)
        let samples = ["Daily (1-day)": [sample(at: -20 * hour, 0.9), sample(at: -hour, 0.25)]]
        let c = card(state(rows: [row(fiveHourLabel, percent: 0.2, elapsed: 0.4, window: fiveHours), daily], samples: samples))
        let chart = try #require(c.burndown)
        #expect(chart.label == "Daily (1-day)")
        #expect(chart.actual.map(\.percent) == [0, 0.25, 0.3])
    }

    @Test func aRestartedWindowBurnsDownFromZero() throws {
        let passed = LimitRow(label: weeklyLabel, percent: 0.12, resetsAt: now.addingTimeInterval(-2 * 24 * hour), windowDuration: week)
        let samples = [weeklyLabel: [sample(at: -3 * 24 * hour, 0.12)]]
        let c = card(state(.codex, rows: [passed], samples: samples))
        let chart = try #require(c.burndown)
        #expect(chart.windowStart == now.addingTimeInterval(-2 * 24 * hour))
        #expect(chart.actual.map(\.percent) == [0, 0])
        #expect(chart.isProjectedReset)
    }

    @Test func noBurndownWithoutKnownLimits() {
        #expect(card(state(rows: [])).burndown == nil)
    }

    // MARK: Lane numbers

    @Test func laneNumbersAndTopThreeModels() {
        let models = ["opus", "sonnet", "haiku", "other"].enumerated().map { index, name in
            ModelUsage(model: name, split: TokenSplit(input: 100 - index * 10, cacheWrite: 0, output: 0, cacheRead: 0))
        }
        let lane = LaneUsage(provider: .claude, buckets: Array(repeating: 0, count: 12), heat: 1_234_567,
                             split: TokenSplit(input: 10, cacheWrite: 20, output: 30, cacheRead: 40),
                             byModel: models, turns: 7, sessions: 2, rate5m: 1500, rate60m: 250)
        let c = card(state(rows: [], lane: lane))
        #expect(c.topModels.map(\.model) == ["opus", "sonnet", "haiku"])
        #expect(c.split == lane.split)
        #expect(c.rate5mText == "1.5K/min")
        #expect(c.rate60mText == "250/min")
        #expect(c.tokensText == "1.2M")
        #expect(c.accountLabel == "dev@example.com")
        #expect(c.title == "Claude")
    }

    @Test func statusStaleAndErrorPassThrough() {
        let c = card(state(rows: [], status: "x", isStale: true, hasError: true))
        #expect(c.status == "x")
        #expect(c.isStale)
        #expect(c.hasError)
    }

    // MARK: Formatting

    @Test(arguments: [
        (30.0, "1m"), (42 * minute, "42m"), (3 * hour + 5 * minute, "3h 05m"),
        (26 * hour, "1d 2h"), (-5.0, "0m"),
    ])
    func durations(interval: TimeInterval, expected: String) {
        #expect(CockpitFormat.duration(interval) == expected)
    }

    @Test(arguments: [(0, "0"), (999, "999"), (1500, "1.5K"), (2_500_000, "2.5M")])
    func tokens(count: Int, expected: String) {
        #expect(CockpitFormat.tokens(count) == expected)
    }

    // MARK: Header

    @Test func headerSumsEveryLane() {
        let claude = LaneUsage(provider: .claude, buckets: [], heat: 1000, split: .zero, byModel: [], turns: 3, sessions: 1, rate5m: 0, rate60m: 0)
        let codex = LaneUsage(provider: .codex, buckets: [], heat: 500, split: .zero, byModel: [], turns: 2, sessions: 2, rate5m: 0, rate60m: 0)
        let viewState = UsageViewState(summary: UsageSummary(bucketStarts: [], lanes: [.claude: claude, .codex: codex]),
                                       providers: [], advice: nil, isAdviceDismissed: false, updatedAt: now)
        let header = CockpitHeader(state: viewState)
        #expect(header.tokensText == "1.5K")
        #expect(header.turns == 5)
        #expect(header.sessions == 3)
        #expect(header.updatedAt == now)
        #expect(viewState.header == header)
    }

    @Test func cardsFollowTheProviderOrderAsOfTheUpdate() {
        let viewState = UsageViewState(summary: UsageSummary(bucketStarts: [], lanes: [:]),
                                       providers: [state(.claude, rows: []), state(.codex, rows: [])],
                                       advice: nil, isAdviceDismissed: false, updatedAt: now)
        #expect(viewState.cards(now: .distantFuture).map(\.provider) == [.claude, .codex])
    }
}
