//
//  CockpitDisplayTests.swift
//  burnbarTests
//
//  The cockpit's pure display decisions: card headline (budget or tokens), status line,
//  spend advice, glow and the advice banner.
//

import Foundation
import Testing
@testable import burnbar

struct CockpitDisplayTests {
    private let weeklyLabel = "Weekly (7-day)"
    private let fiveHourLabel = "Session (5-hour)"

    private func lane(heat: Int = 0, turns: Int = 0, sessions: Int = 0, rate5m: Double = 0,
                      split: TokenSplit = .zero) -> LaneUsage {
        LaneUsage(provider: .claude, buckets: [0, 4, 9], heat: heat, split: split, byModel: [],
                  turns: turns, sessions: sessions, rate5m: rate5m, rate60m: 0)
    }

    private func card(_ rows: [LimitRow], lane: LaneUsage? = nil, status: String? = nil,
                      hasError: Bool = false) -> ProviderCard {
        let limits = rows.map { row in
            let pace = PaceCalculator.pace(for: row, samples: [], now: now)
            return LimitRowState(row: pace?.row ?? row, pace: pace)
        }
        let state = ProviderState(provider: .claude, lane: lane ?? .empty(.claude), limits: limits, measuredAt: now,
                                  status: status, isStale: false, hasError: hasError, account: nil)
        return ProviderCard(state: state, now: now)
    }

    // MARK: By model

    @Test func modelShareIsOfAllTheCardTokensNotJustTheShownModels() {
        let models = [400, 300, 200, 100].enumerated().map { index, heat in
            ModelUsage(model: "m\(index)", split: TokenSplit(input: heat, cacheWrite: 0, output: 0, cacheRead: 0))
        }
        let lane = LaneUsage(provider: .claude, buckets: [], heat: 1000, split: .zero, byModel: models,
                             turns: 1, sessions: 1, rate5m: 0, rate60m: 0)
        let c = card([], lane: lane)
        #expect(c.topModels.count == 3)
        #expect(c.share(of: c.topModels[0]) == 0.4)
        #expect(c.share(of: c.topModels[2]) == 0.2)
    }

    // MARK: Headline

    @Test func budgetHeadlineShowsTheSpentShareOfTheWeeklyBudget() {
        let c = card([row(weeklyLabel, percent: 0.1, elapsed: 0.5)], lane: lane(heat: 10_400_000))
        let headline = c.headline(.budget, windowLabel: "6 h")
        #expect(headline.mode == .budget)
        #expect(headline.value == "10%")
        #expect(headline.caption == "of weekly budget spent")
        #expect(headline.detail == "10.4M tokens · resets in \(CockpitFormat.duration(0.5 * week))")
    }

    @Test func budgetHeadlineNamesTheFiveHourWindowWhenItIsTheOnlyOne() {
        let c = card([row(fiveHourLabel, percent: 0.42, elapsed: 0.5, window: fiveHours)])
        #expect(c.headline(.budget, windowLabel: "6 h").caption == "of 5-hour budget spent")
    }

    @Test func tokensHeadlineShowsTheWindowTotals() {
        let c = card([row(weeklyLabel, percent: 0.1, elapsed: 0.5)], lane: lane(heat: 623_000, turns: 201, sessions: 6))
        let headline = c.headline(.tokens, windowLabel: "6 h")
        #expect(headline.mode == .tokens)
        #expect(headline.value == "623K")
        #expect(headline.caption == "tokens · last 6 h · 201 turns · 6 sessions")
        #expect(headline.detail == nil)
    }

    @Test func budgetHeadlineFallsBackToTokensWithoutLimits() {
        let c = card([], lane: lane(heat: 75_000, turns: 5, sessions: 1))
        let headline = c.headline(.budget, windowLabel: "1 d")
        #expect(headline.mode == .tokens)
        #expect(headline.value == "75.0K")
        #expect(headline.caption == "tokens · last 1 d · 5 turns · 1 sessions")
    }

    @Test(arguments: [(0, "0"), (999, "999"), (1500, "1.5K"), (99_900, "99.9K"), (623_000, "623K"), (2_500_000, "2.5M")])
    func headlineTokens(count: Int, expected: String) {
        #expect(CockpitFormat.headlineTokens(count) == expected)
    }

    // MARK: Status line

    @Test func bankedStatusSaysHowMuchAndHowLong() {
        let c = card([row(weeklyLabel, percent: 0.3, elapsed: 0.5)])
        #expect(c.statusLine == CardStatus(title: "BANKED 20%", detail: "\(CockpitFormat.duration(0.2 * week)) in the bank", tone: .good))
    }

    @Test func onPaceStatus() {
        let c = card([row(weeklyLabel, percent: 0.49, elapsed: 0.5)])
        #expect(c.statusLine == CardStatus(title: "ON PACE", detail: "spend evenly and it lasts", tone: .neutral))
    }

    @Test func overPaceStatusSaysWhenToComeBack() {
        let c = card([row(weeklyLabel, percent: 0.6, elapsed: 0.5)])
        #expect(c.statusLine == CardStatus(title: "COME BACK IN \(CockpitFormat.duration(0.1 * week))", detail: "if you stop now", tone: .warn))
    }

    @Test func spentStatusIsBackAtTheReset() {
        let c = card([row(weeklyLabel, percent: 1.0, elapsed: 0.9)])
        #expect(c.statusLine == CardStatus(title: "BACK AT THE RESET", detail: "in \(CockpitFormat.duration(0.1 * week))", tone: .bad))
    }

    @Test func nearlySpentFiveHourStatus() {
        let c = card([row(fiveHourLabel, percent: 0.95, elapsed: 0.5, window: fiveHours), row(weeklyLabel, percent: 0.3, elapsed: 0.5)])
        #expect(c.statusLine == CardStatus(title: "COME BACK IN \(CockpitFormat.duration(2.5 * hour))", detail: "5-hour nearly out", tone: .bad))
    }

    @Test func unknownLimitsStatus() {
        #expect(card([]).statusLine == CardStatus(title: "NO PLAN READING", detail: "showing tokens only", tone: .neutral))
        #expect(card([], status: "Claude limits unreachable", hasError: true).statusLine
            == CardStatus(title: "NO PLAN READING", detail: "Claude limits unreachable", tone: .bad))
    }

    // MARK: Spend advice

    @Test func spendAdviceFollowsThePace() {
        #expect(card([row(weeklyLabel, percent: 0.1, elapsed: 0.5)]).spendAdvice == "Spend up to 1.1% an hour and it lasts to the reset")
        #expect(card([row(weeklyLabel, percent: 0.6, elapsed: 0.5)]).spendAdvice == "Slow to 0.5% an hour to make it to the reset")
        #expect(card([row(weeklyLabel, percent: 1.0, elapsed: 0.9)]).spendAdvice == "Nothing left until it resets")
        #expect(card([]).spendAdvice == nil)
    }

    // MARK: Burn and token mix

    @Test func averageRateOverTheWindow() {
        let c = card([], lane: lane(heat: 36_000))
        #expect(c.averageRateText(window: 6 * hour) == "100/min")
        #expect(c.averageRateText(window: 0) == "0/min")
    }

    @Test func cacheReadShareOfEverythingTakenIn() {
        #expect(TokenSplit(input: 10, cacheWrite: 20, output: 30, cacheRead: 70).cacheReadShare == 0.7)
        #expect(TokenSplit.zero.cacheReadShare == nil)
    }

    @Test func cardsCarryTheLaneBucketsAndEvenPaceMarks() throws {
        let c = card([row(weeklyLabel, percent: 0.1, elapsed: 0.5)], lane: lane(heat: 1))
        #expect(c.buckets == [0, 4, 9])
        let elapsed = try #require(c.lines.first?.elapsed)
        #expect(abs(elapsed - 0.5) < 0.001)
    }

    // MARK: Glow

    @Test(arguments: [
        (0.1, 0.5, GlowWhen.over, nil as CardGlow?),
        (0.6, 0.5, GlowWhen.over, CardGlow(intensity: 0.6, isAlarm: true)),
        (0.9, 0.5, GlowWhen.over, CardGlow(intensity: 1, isAlarm: true)),
        (0.9, 0.5, GlowWhen.never, nil),
        (0.5, 0.5, GlowWhen.spent, CardGlow(intensity: 0.5, isAlarm: false)),
        (0.95, 0.99, GlowWhen.spent, CardGlow(intensity: 0.95, isAlarm: true)),
        (0.02, 0.5, GlowWhen.spent, nil),
    ])
    func glowFollowsThePaceAndSpend(percent: Double, elapsed: Double, when: GlowWhen, expected: CardGlow?) {
        let c = card([row(weeklyLabel, percent: percent, elapsed: elapsed)])
        #expect(CardGlow.glow(for: c, when: when) == expected)
    }

    @Test func burningGlowNeedsTokensInTheLastFiveMinutes() {
        #expect(CardGlow.glow(for: card([], lane: lane(rate5m: 120)), when: .burning) == CardGlow(intensity: 0.8, isAlarm: false))
        #expect(CardGlow.glow(for: card([], lane: lane(rate5m: 0)), when: .burning) == nil)
    }

    @Test func spentGlowNeedsABudget() {
        #expect(CardGlow.glow(for: card([]), when: .spent) == nil)
    }

    // MARK: Advice banner

    @Test func adviceBannerUsesTheAdvisedCard() {
        let c = card([row(weeklyLabel, percent: 0.3, elapsed: 0.5)])
        let banner = AdviceBanner(advice: .keepUsing(.claude), cards: [c])
        #expect(banner.title == "KEEP USING CLAUDE")
        #expect(banner.provider == .claude)
        #expect(banner.detail == "banked 20% · \(CockpitFormat.duration(0.2 * week)) in the bank · resets in \(CockpitFormat.duration(0.5 * week))")
    }

    @Test func spentAdviceBannerHasNoProvider() {
        let banner = AdviceBanner(advice: .spent, cards: [])
        #expect(banner.title == "SPENT")
        #expect(banner.provider == nil)
        #expect(banner.detail == nil)
    }
}
