//
//  AdviceEngineTests.swift
//  burnbarTests
//

import Foundation
import Testing
@testable import burnbar

struct AdviceEngineTests {
    /// A healthy five-hour row: 20% used, 40% elapsed, no rate.
    private let calmFiveHour = pace(percent: 0.2, elapsed: 0.4, window: fiveHours)

    private func sub(_ provider: Provider, fiveHour: Pace? = nil, weeklyPercent: Double, weeklyElapsed: Double) -> SubscriptionPace {
        SubscriptionPace(provider: provider, fiveHour: fiveHour ?? calmFiveHour, weekly: pace(percent: weeklyPercent, elapsed: weeklyElapsed))
    }

    private func advise(_ subs: [SubscriptionPace], current: Provider? = .claude) -> Advice {
        AdviceEngine.advise(subs, current: current, now: now)
    }

    @Test func spentWhenEverySubIsBlocked() {
        let blocked = pace(percent: 0.9, elapsed: 0.5, window: fiveHours)
        let advice = advise([sub(.claude, fiveHour: blocked, weeklyPercent: 0.1, weeklyElapsed: 0.5),
                             sub(.codex, fiveHour: blocked, weeklyPercent: 0.1, weeklyElapsed: 0.5)])
        #expect(advice == .spent)
        #expect(advice.text == "SPENT")
    }

    @Test func keepUsingWhenNothingIsMeaningfullyBetter() {
        let advice = advise([sub(.claude, weeklyPercent: 0.40, weeklyElapsed: 0.50),   // banked 0.10
                             sub(.codex, weeklyPercent: 0.39, weeklyElapsed: 0.50)])   // banked 0.11 < 1.15×
        #expect(advice == .keepUsing(.claude))
        #expect(advice.text == "KEEP USING CLAUDE")
    }

    @Test func switchesWhenOtherIsFifteenPercentBetter() {
        let advice = advise([sub(.claude, weeklyPercent: 0.40, weeklyElapsed: 0.50),
                             sub(.codex, weeklyPercent: 0.30, weeklyElapsed: 0.50)])
        #expect(advice == .useNext(.codex))
        #expect(advice.text == "USE CODEX NEXT")
    }

    @Test func candidateNeedsTwoPercentBanked() {
        let advice = advise([sub(.claude, weeklyPercent: 0.505, weeklyElapsed: 0.50),  // banked -0.005
                             sub(.codex, weeklyPercent: 0.485, weeklyElapsed: 0.50)])  // banked 0.015
        #expect(advice == .keepUsing(.claude))
    }

    @Test func blockedFiveHourMovesToAlternative() {
        let blocked = pace(percent: 0.92, elapsed: 0.5, window: fiveHours)
        let advice = advise([sub(.claude, fiveHour: blocked, weeklyPercent: 0.2, weeklyElapsed: 0.5),
                             sub(.codex, weeklyPercent: 0.4, weeklyElapsed: 0.5)])
        #expect(advice == .useNext(.codex))
    }

    @Test func fullWithinHalfHourCountsAsBlocked() {
        // 80% used, 0.5/h → dry in 24 min.
        let samples = [sample(at: -24 * minute, 0.6), sample(at: 0, 0.8)]
        let draining = pace(percent: 0.8, elapsed: 0.5, window: fiveHours, samples: samples)
        #expect(AdviceEngine.isBlocked(SubscriptionPace(provider: .claude, fiveHour: draining, weekly: nil), now: now))
    }

    @Test func dryAfterResetIsNotBlocked() {
        // Reset in 10 min; 50% used at 1.2/h → dry in 25 min, after the reset.
        let samples = [sample(at: -20 * minute, 0.1), sample(at: 0, 0.5)]
        let late = pace(percent: 0.5, elapsed: 1 - 10.0 / 300.0, window: fiveHours, samples: samples)
        #expect(late.dryAt! > late.row.resetsAt)
        #expect(!AdviceEngine.isBlocked(SubscriptionPace(provider: .claude, fiveHour: late, weekly: nil), now: now))
    }

    @Test func fullWeekCountsAsBlocked() {
        let full = SubscriptionPace(provider: .claude, fiveHour: calmFiveHour, weekly: pace(percent: 0.995, elapsed: 0.9))
        let almost = SubscriptionPace(provider: .claude, fiveHour: calmFiveHour, weekly: pace(percent: 0.994, elapsed: 0.99))
        #expect(AdviceEngine.isBlocked(full, now: now))
        #expect(!AdviceEngine.isBlocked(almost, now: now))
    }

    @Test func restUntilWeeklyResetWhenWeekIsFull() {
        let advice = advise([sub(.claude, weeklyPercent: 0.996, weeklyElapsed: 0.9),
                             sub(.codex, weeklyPercent: 0.5, weeklyElapsed: 0.5)])   // open, nothing banked
        // Weekly reset in 16.8 h outlasts back-on-pace (16.128 h).
        #expect(advice == .rest(.claude, for: 60_480))
        #expect(advice.text == "CLAUDE REST 17H")
    }

    @Test func useNowWhenBankedWeekEndsSoon() {
        // Codex: 10 h left of 168 h, banked well over 2%.
        let advice = advise([sub(.claude, weeklyPercent: 0.2, weeklyElapsed: 0.5),
                             sub(.codex, weeklyPercent: 0.5, weeklyElapsed: 1 - 10.0 / 168.0)])
        #expect(advice == .useNow(.codex))
        #expect(advice.text == "USE CODEX NOW")
    }

    @Test func noUseNowOutsideTheEndgame() {
        // 30 h left > 15% of a week (25.2 h).
        let advice = advise([sub(.claude, weeklyPercent: 0.2, weeklyElapsed: 0.5),
                             sub(.codex, weeklyPercent: 0.5, weeklyElapsed: 1 - 30.0 / 168.0)])
        #expect(advice == .keepUsing(.claude))
    }

    @Test func restUntilBackOnPaceWhenOverWithNoAlternative() {
        let blocked = pace(percent: 0.95, elapsed: 0.5, window: fiveHours)
        let advice = advise([sub(.claude, weeklyPercent: 0.6, weeklyElapsed: 0.4),
                             sub(.codex, fiveHour: blocked, weeklyPercent: 0.1, weeklyElapsed: 0.5)])
        // backOnPaceAt = reset − L(1 − p) → 100.8 h − 67.2 h = 33.6 h.
        #expect(advice == .rest(.claude, for: 120_960))
        #expect(advice.text == "CLAUDE REST 34H")
    }

    @Test func restUntilFiveHourResetWhenAlternativeHasNothingBanked() {
        let blocked = pace(percent: 0.95, elapsed: 0.5, window: fiveHours)
        let advice = advise([sub(.claude, fiveHour: blocked, weeklyPercent: 0.2, weeklyElapsed: 0.5),
                             sub(.codex, weeklyPercent: 0.5, weeklyElapsed: 0.5)])
        #expect(advice == .rest(.claude, for: 9_000))
    }

    @Test func warnsWhenFiveHourRunsOutBeforeReset() {
        // 60% used at 0.6/h → dry in 40 min, reset in 2.5 h.
        let samples = [sample(at: -30 * minute, 0.3), sample(at: 0, 0.6)]
        let draining = pace(percent: 0.6, elapsed: 0.5, window: fiveHours, samples: samples)
        let advice = advise([sub(.claude, fiveHour: draining, weeklyPercent: 0.2, weeklyElapsed: 0.5)])
        #expect(advice == .fiveHourOut(.claude, in: 2_400))
        #expect(advice.text == "CLAUDE 5-HOUR OUT IN 40M")
    }

    @Test func noCurrentPicksBestBanked() {
        let advice = advise([sub(.claude, weeklyPercent: 0.4, weeklyElapsed: 0.5),
                             sub(.codex, weeklyPercent: 0.1, weeklyElapsed: 0.5)], current: nil)
        #expect(advice == .keepUsing(.codex))
    }

    @Test func severityOrdersAdviceForDismissal() {
        #expect(Advice.spent.severity > Advice.rest(.claude, for: hour).severity)
        #expect(Advice.rest(.claude, for: hour).severity > Advice.fiveHourOut(.claude, in: hour).severity)
        #expect(Advice.fiveHourOut(.claude, in: hour).severity > Advice.useNext(.codex).severity)
        #expect(Advice.useNext(.codex).severity > Advice.keepUsing(.claude).severity)
    }

    @Test(arguments: [(40 * minute, "40M"), (59 * minute, "59M"), (90 * minute, "2H"), (8 * hour, "8H"), (20, "1M")])
    func durationLabels(interval: TimeInterval, expected: String) {
        #expect(Advice.durationLabel(interval) == expected)
    }

    @Test func identityIsTheKindAndProviderIgnoringDurations() {
        #expect(Advice.rest(.claude, for: 8 * hour).identity == Advice.rest(.claude, for: 7 * hour).identity)
        #expect(Advice.fiveHourOut(.codex, in: 40 * minute).identity == "fiveHourOut.codex")
        #expect(Advice.useNext(.codex).identity != Advice.useNext(.claude).identity)
        #expect(Advice.useNext(.codex).identity != Advice.useNow(.codex).identity)
        #expect(Advice.spent.identity == "spent")
    }

    @Test func aWeeklyOnlySubWithARestartedWeekIsACandidate() throws {
        // Codex reports only a weekly window whose reset passed 2 days ago: 0% used, 2/7 banked.
        let restarted = LimitRow(label: "Weekly (7-day)", percent: 0.12, resetsAt: now.addingTimeInterval(-2 * 24 * hour), windowDuration: week)
        let weekly = try #require(PaceCalculator.pace(for: restarted, samples: [], now: now))
        let codex = SubscriptionPace(provider: .codex, fiveHour: nil, weekly: weekly)
        let claude = sub(.claude, weeklyPercent: 0.8, weeklyElapsed: 0.5)
        #expect(advise([claude, codex]) == .useNext(.codex))
        #expect(AdviceEngine.isBlocked(codex, now: now) == false)
    }

    // MARK: Suggestions off

    private func warn(_ subs: [SubscriptionPace], current: Provider? = .claude) -> Advice? {
        AdviceEngine.advise(subs, current: current, now: now, suggestingNext: false)
    }

    @Test func noSuggestionWithoutAWarning() {
        let subs = [sub(.claude, weeklyPercent: 0.40, weeklyElapsed: 0.50), sub(.codex, weeklyPercent: 0.30, weeklyElapsed: 0.50)]
        #expect(advise(subs) == .useNext(.codex))
        #expect(warn(subs) == nil)
    }

    @Test func noUseNowWithoutSuggestions() {
        let subs = [sub(.claude, weeklyPercent: 0.40, weeklyElapsed: 0.50), sub(.codex, weeklyPercent: 0.30, weeklyElapsed: 0.95)]
        #expect(advise(subs) == .useNow(.codex))
        #expect(warn(subs) == nil)
    }

    @Test func anOverPaceSubRestsInsteadOfSwitching() {
        let subs = [sub(.claude, weeklyPercent: 0.8, weeklyElapsed: 0.5), sub(.codex, weeklyPercent: 0.2, weeklyElapsed: 0.5)]
        guard case .rest(.claude, _) = warn(subs) else {
            Issue.record("expected REST CLAUDE, got \(String(describing: warn(subs)))")
            return
        }
    }

    @Test func spentStillShowsWithoutSuggestions() {
        let blocked = pace(percent: 0.9, elapsed: 0.5, window: fiveHours)
        #expect(warn([sub(.claude, fiveHour: blocked, weeklyPercent: 0.1, weeklyElapsed: 0.5)]) == .spent)
    }

    @Test func aFiveHourRowRunsOutAtNinetyPercentOrWhenDryBeforeItsReset() {
        #expect(AdviceEngine.isFiveHourRunningOut(pace(percent: 0.9, elapsed: 0.5, window: fiveHours)))
        #expect(!AdviceEngine.isFiveHourRunningOut(calmFiveHour))
    }
}
