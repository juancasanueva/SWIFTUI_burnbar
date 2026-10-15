//
//  UsageStoreTests.swift
//  burnbarTests
//

import Foundation
import Testing
@testable import burnbar

@MainActor
final class UsageStoreTests {
    private let clock = TestClock(now)
    private let claudeCollector = StubCollector()
    private let codexCollector = StubCollector()
    private let claudeLimits = StubLimits()
    private let codexLimits = StubLimits()
    private let samples = StubSampleStore()
    private let defaults: UserDefaults
    private let suiteName: String

    init() {
        (defaults, suiteName) = makeTestDefaults()
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func store(
        interval: Duration = .seconds(5),
        claudeLimits: (any LimitsSource)? = nil,
        accounts: any AccountReading = StubAccounts(),
        isInert: Bool = false
    ) -> UsageStore {
        let clock = clock
        return UsageStore(
            collectors: [.claude: claudeCollector, .codex: codexCollector],
            limits: [.claude: claudeLimits ?? self.claudeLimits, .codex: codexLimits],
            samples: samples,
            accounts: accounts,
            defaults: defaults,
            collectInterval: interval,
            now: { clock.now },
            isInert: isInert
        )
    }

    /// Codex over its weekly pace and burning now; Claude well under pace.
    private func seedCodexOverAndClaudeBanked() {
        claudeCollector.set([])
        codexCollector.set([event(.codex, at: -600, input: 500, output: 100)])
        claudeLimits.set(limitSnapshot(.claude, fiveHour: 0.1, weekly: 0.2))
        codexLimits.set(limitSnapshot(.codex, fiveHour: 0.3, weekly: 0.8))
    }

    /// Claude over its weekly pace and burning now; Codex well under pace.
    private func seedOverAndBanked() {
        claudeCollector.set([event(.claude, at: -600, input: 500, output: 100)])
        claudeLimits.set(limitSnapshot(.claude, fiveHour: 0.3, weekly: 0.8))
        codexLimits.set(limitSnapshot(.codex, fiveHour: 0.1, weekly: 0.2))
    }

    // MARK: Tick

    @Test func aTickPublishesLanesLimitsAndAccounts() async throws {
        claudeCollector.set([event(.claude, at: -600, input: 1000, output: 200, session: "a")])
        codexCollector.set([event(.codex, at: -60, input: 50, session: "b")])
        claudeLimits.set(limitSnapshot(.claude, fiveHour: 0.3, weekly: 0.42))
        codexLimits.set(limitSnapshot(.codex, fiveHour: 0.1, weekly: 0.31))
        let sut = store()
        await sut.refresh()

        let state = sut.state
        #expect(state.updatedAt == now)
        #expect(state.providers.map(\.provider) == [.claude, .codex])
        let claude = try #require(state.provider(.claude))
        #expect(claude.lane.heat == 1200)
        #expect(claude.weekly?.percent == 0.42)
        #expect(claude.fiveHour?.percent == 0.3)
        #expect(claude.limits.map(\.row.label) == ["Session (5-hour)", "Weekly (7-day)"])
        #expect(claude.account?.label == "dev@example.com")
        #expect(claude.hasError == false)
        #expect(claude.isStale == false)
        #expect(state.provider(.codex)?.lane.heat == 50)
        #expect(state.provider(.codex)?.account?.label == "API key")
        #expect(state.summary.peakBucketHeat == 1200)
        #expect(state.statusText == nil)
    }

    @Test func limitsRefreshEveryFiveMinutesAndWhenForced() async throws {
        let sut = store()
        await sut.refresh()
        clock.advance(5)
        await sut.refresh()
        #expect(claudeLimits.forces == [false])
        #expect(claudeCollector.calls == 2)

        clock.advance(295)
        await sut.refresh()
        #expect(claudeLimits.forces == [false, false])
        #expect(codexLimits.forces == [false, false])

        await sut.refreshLimits(force: true)
        #expect(claudeLimits.forces == [false, false, true])
        #expect(codexLimits.forces == [false, false, true])
    }

    @Test func snapshotsAreRecordedAndTheirSamplesFeedThePace() async throws {
        let snapshot = limitSnapshot(.claude, fiveHour: 0.3, weekly: 0.42)
        claudeLimits.set(snapshot)
        // 4% per hour over the last 30 minutes of the 5-hour window.
        samples.seed(.claude, label: "Session (5-hour)", [sample(at: -1800, 0.28), sample(at: 0, 0.30)])
        let sut = store()
        await sut.refresh()

        #expect(samples.recorded == [snapshot])
        let rate = try #require(sut.state.provider(.claude)?.fiveHour?.ratePerHour)
        #expect(abs(rate - 0.04) < 1e-9)
        // The same samples reach the view state for the burndown chart.
        #expect(sut.state.provider(.claude)?.samples["Session (5-hour)"]?.map(\.percent) == [0.28, 0.30])
    }

    @Test func aMissingSnapshotKeepsTheLastOne() async throws {
        codexLimits.set(limitSnapshot(.codex, fiveHour: 0.1, weekly: 0.31))
        let sut = store()
        await sut.refresh()
        codexLimits.set(nil)
        await sut.refreshLimits(force: true)
        #expect(sut.state.provider(.codex)?.weekly?.percent == 0.31)
    }

    // MARK: Advice

    @Test func advisesSwitchingAwayFromAnOverPaceProvider() async throws {
        seedOverAndBanked()
        let sut = store()
        await sut.refresh()
        #expect(sut.state.advice == .useNext(.codex))
        #expect(sut.state.visibleAdvice == .useNext(.codex))
    }

    @Test func noAdviceWithoutAnyKnownLimits() async throws {
        claudeCollector.set([event(.claude, at: -600, input: 500)])
        let sut = store()
        await sut.refresh()
        #expect(sut.state.advice == nil)
    }

    @Test func dismissedAdviceStaysHiddenAcrossLaunchesUntilItGetsWorse() async throws {
        seedOverAndBanked()
        let sut = store()
        await sut.refresh()
        sut.dismissAdvice()
        #expect(sut.state.visibleAdvice == nil)
        #expect(sut.state.advice == .useNext(.codex))
        #expect(defaults.string(forKey: UsageStore.DefaultsKey.dismissedIdentity) == "useNext.codex")
        #expect(defaults.integer(forKey: UsageStore.DefaultsKey.dismissedSeverity) == 1)

        // A relaunch remembers the dismissal.
        let relaunched = store()
        await relaunched.refresh()
        #expect(relaunched.state.visibleAdvice == nil)

        // Both 5-hour windows nearly full: SPENT is worse, so it shows and the dismissal is cleared.
        claudeLimits.set(limitSnapshot(.claude, fiveHour: 0.95, weekly: 0.8))
        codexLimits.set(limitSnapshot(.codex, fiveHour: 0.95, weekly: 0.2))
        await relaunched.refreshLimits(force: true)
        #expect(relaunched.state.visibleAdvice == .spent)
        #expect(defaults.object(forKey: UsageStore.DefaultsKey.dismissedSeverity) == nil)
    }

    @Test func theSameAdviceStaysHiddenWhileItPersists() async throws {
        seedOverAndBanked()
        let sut = store()
        await sut.refresh()
        sut.dismissAdvice()
        clock.advance(400)
        await sut.refresh()
        await sut.refreshLimits(force: true)
        #expect(sut.state.advice == .useNext(.codex))
        #expect(sut.state.visibleAdvice == nil)
    }

    @Test func aDifferentAdviceOfEqualSeverityShows() async throws {
        seedOverAndBanked()
        let sut = store()
        await sut.refresh()
        sut.dismissAdvice()
        #expect(sut.state.visibleAdvice == nil)

        seedCodexOverAndClaudeBanked()
        await sut.refresh()
        await sut.refreshLimits(force: true)
        #expect(sut.state.advice == .useNext(.claude))
        #expect(sut.state.advice?.severity == Advice.useNext(.codex).severity)
        #expect(sut.state.visibleAdvice == .useNext(.claude))
    }

    @Test func aWorseAdviceShowsAndClearsTheDismissal() async throws {
        seedOverAndBanked()
        let sut = store()
        await sut.refresh()
        sut.dismissAdvice()

        claudeLimits.set(limitSnapshot(.claude, fiveHour: 0.95, weekly: 0.8))
        codexLimits.set(limitSnapshot(.codex, fiveHour: 0.95, weekly: 0.2))
        await sut.refreshLimits(force: true)
        #expect(sut.state.visibleAdvice == .spent)
        #expect(defaults.object(forKey: UsageStore.DefaultsKey.dismissedIdentity) == nil)
        #expect(defaults.object(forKey: UsageStore.DefaultsKey.dismissedSeverity) == nil)
    }

    @Test func noAdviceFromLiveLimitsClearsTheDismissal() async throws {
        seedOverAndBanked()
        let sut = store()
        await sut.refresh()
        sut.dismissAdvice()

        // Live snapshots that carry no limit rows: genuinely nothing to advise.
        claudeLimits.set(LimitSnapshot(provider: .claude, rows: [], measuredAt: now))
        codexLimits.set(LimitSnapshot(provider: .codex, rows: [], measuredAt: now))
        let live = store()
        await live.refresh()
        #expect(live.state.advice == nil)
        #expect(defaults.object(forKey: UsageStore.DefaultsKey.dismissedIdentity) == nil)
        #expect(defaults.object(forKey: UsageStore.DefaultsKey.dismissedSeverity) == nil)

        seedOverAndBanked()
        await live.refreshLimits(force: true)
        #expect(live.state.visibleAdvice == .useNext(.codex))
    }

    @Test func aTransientLimitsFailureKeepsTheDismissal() async throws {
        seedOverAndBanked()
        let sut = store()
        await sut.refresh()
        sut.dismissAdvice()

        claudeLimits.set(LimitSnapshot(provider: .claude, rows: [], measuredAt: now, status: "x", limitsLive: false))
        codexLimits.set(LimitSnapshot(provider: .codex, rows: [], measuredAt: now, status: "y", limitsLive: false))
        let failing = store()
        await failing.refresh()
        #expect(failing.state.advice == nil)
        #expect(defaults.string(forKey: UsageStore.DefaultsKey.dismissedIdentity) == "useNext.codex")

        seedOverAndBanked()
        await failing.refreshLimits(force: true)
        #expect(failing.state.advice == .useNext(.codex))
        #expect(failing.state.visibleAdvice == nil)
    }

    @Test func usagePublishedBeforeTheFirstLimitsKeepsTheDismissal() async throws {
        seedOverAndBanked()
        let sut = store()
        await sut.refresh()
        sut.dismissAdvice()

        let relaunched = store()
        await relaunched.collectUsage()
        #expect(relaunched.state.advice == nil)
        #expect(defaults.string(forKey: UsageStore.DefaultsKey.dismissedIdentity) == "useNext.codex")
        await relaunched.refreshLimits(force: false)
        #expect(relaunched.state.advice == .useNext(.codex))
        #expect(relaunched.state.visibleAdvice == nil)
    }

    @Test func dismissingWithoutAdviceDoesNothing() async throws {
        let sut = store()
        await sut.refresh()
        sut.dismissAdvice()
        #expect(defaults.object(forKey: UsageStore.DefaultsKey.dismissedSeverity) == nil)
    }

    // MARK: Errors and staleness

    @Test func failedLimitsSurfaceAsStatusAndAnErrorLane() async throws {
        let status = "Claude Code sign-in not found — run claude to sign in"
        claudeLimits.set(LimitSnapshot(provider: .claude, rows: [], measuredAt: now, status: status, limitsLive: false))
        let sut = store()
        await sut.refresh()

        let claude = try #require(sut.state.provider(.claude))
        #expect(claude.hasError)
        #expect(claude.status == status)
        #expect(sut.state.provider(.codex)?.status == "No Codex limits yet")
        #expect(sut.state.provider(.codex)?.hasError == false)
        #expect(sut.state.statusText == "\(status)\nNo Codex limits yet")
    }

    @Test func lastKnownRowsAreNotAnErrorLane() async throws {
        claudeLimits.set(limitSnapshot(.claude, fiveHour: 0.3, weekly: 0.4, status: "Claude limits unreachable", live: false))
        let sut = store()
        await sut.refresh()
        #expect(sut.state.provider(.claude)?.hasError == false)
        #expect(sut.state.provider(.claude)?.status == "Claude limits unreachable")
    }

    @Test func oldLimitsStayStaleAndAPassedResetRestartsAtZero() async throws {
        let measured = now.addingTimeInterval(-1000)
        let passed = LimitRow(label: "Session (5-hour)", percent: 0.5, resetsAt: now.addingTimeInterval(-1), windowDuration: fiveHours)
        codexLimits.set(LimitSnapshot(provider: .codex, rows: [passed], measuredAt: measured))
        let sut = store()
        await sut.refresh()
        let codex = try #require(sut.state.provider(.codex))
        #expect(codex.isStale)
        #expect(codex.limits.count == 1)
        let fiveHour = try #require(codex.fiveHour)
        #expect(fiveHour.percent == 0)
        #expect(fiveHour.isProjectedReset)
        #expect(codex.limits[0].row.percent == 0)
        #expect(codex.limits[0].row.resetsAt == now.addingTimeInterval(fiveHours - 1))
    }

    @Test func aWeeklyOnlyProviderHasNoFiveHourRow() async throws {
        // This account's Codex `primary` is the weekly window and there is no 5-hour window.
        let weekly = LimitRow(label: LimitRow.label(windowMinutes: 10080), percent: 0.12,
                              resetsAt: now.addingTimeInterval(3 * 24 * hour), windowDuration: 10080 * 60)
        codexLimits.set(LimitSnapshot(provider: .codex, rows: [weekly], measuredAt: now))
        claudeLimits.set(limitSnapshot(.claude, fiveHour: 0.21, weekly: 0.08))
        let sut = store()
        await sut.refresh()
        let codex = try #require(sut.state.provider(.codex))
        #expect(codex.fiveHour == nil)
        #expect(codex.weekly?.percent == 0.12)
        #expect(codex.weekly?.isProjectedReset == false)
        #expect(sut.state.advice != nil)
        #expect(sut.state.accessibilitySummary.hasPrefix("Claude 8% weekly, Codex 12% weekly"))
    }

    @Test func adviceCountsARestartedWeeklyRowAsFresh() async throws {
        // Claude over its weekly pace and burning; Codex's only (weekly) row reset 2 days ago.
        claudeCollector.set([event(.claude, at: -600, input: 500, output: 100)])
        claudeLimits.set(limitSnapshot(.claude, fiveHour: 0.3, weekly: 0.8))
        let passed = LimitRow(label: "Weekly (7-day)", percent: 0.12, resetsAt: now.addingTimeInterval(-2 * 24 * hour), windowDuration: week)
        codexLimits.set(LimitSnapshot(provider: .codex, rows: [passed], measuredAt: now.addingTimeInterval(-6 * 24 * hour)))
        let sut = store()
        await sut.refresh()
        let codex = try #require(sut.state.provider(.codex))
        #expect(codex.isStale)
        #expect(codex.weekly?.percent == 0)
        #expect(codex.weekly?.isProjectedReset == true)
        #expect(sut.state.advice == .useNext(.codex))
    }

    // MARK: Accessibility

    @Test func accessibilitySummaryNamesWeeklyUseAndAdvice() async throws {
        seedOverAndBanked()
        let sut = store()
        await sut.refresh()
        #expect(sut.state.accessibilitySummary == "Claude 80% weekly, Codex 20% weekly, advice: use Codex next")
    }

    @Test func accessibilitySummaryCoversUnknownAndFailedLimits() async throws {
        claudeLimits.set(LimitSnapshot(provider: .claude, rows: [], measuredAt: now, status: "x", limitsLive: false))
        let sut = store()
        await sut.refresh()
        #expect(sut.state.accessibilitySummary == "Claude limits unavailable, Codex weekly unknown")
    }

    // MARK: Non-blocking limits

    @Test func usageIsPublishedWhileLimitsAreBlocked() async throws {
        claudeCollector.set([event(.claude, at: -600, input: 1000)])
        let gated = GatedLimits()
        let sut = store(claudeLimits: gated)
        let tick = Task { await sut.refresh() }
        try await waitUntil { gated.forces.count == 1 }
        try await waitOnMain { sut.state.provider(.claude)?.lane.heat == 1000 }
        gated.open()
        await tick.value
    }

    @Test func theLoopKeepsCollectingWhileLimitsAreBlocked() async throws {
        let gated = GatedLimits()
        let sut = store(interval: .milliseconds(20), claudeLimits: gated)
        sut.start()
        let collector = claudeCollector
        try await waitUntil { collector.calls >= 3 }
        #expect(gated.forces == [false])
        claudeCollector.set([event(.claude, at: -60, input: 42)])
        try await waitOnMain { sut.state.provider(.claude)?.lane.heat == 42 }
        sut.stop()
        gated.open()
    }

    @Test func aForceDuringAnInFlightFetchRunsExactlyOneFollowUp() async throws {
        let gated = GatedLimits(limitSnapshot(.claude, fiveHour: 0.3, weekly: 0.42))
        let sut = store(claudeLimits: gated)
        let first = Task { await sut.refreshLimits(force: false) }
        try await waitUntil { gated.forces.count == 1 }

        let second = Task { await sut.refreshLimits(force: true) }
        let third = Task { await sut.refreshLimits(force: true) }
        // Both extra callers are parked on the in-flight fetch before the gate opens.
        try await waitOnMain { sut.limitsFetchWaiters == 2 }
        #expect(gated.forces == [false])

        gated.open()
        await first.value
        await second.value
        await third.value
        #expect(gated.forces == [false, true])
        #expect(codexLimits.forces == [false, true])
        #expect(sut.state.provider(.claude)?.weekly?.percent == 0.42)
        #expect(sut.limitsFetchWaiters == 0)
    }

    @Test func aSecondForcedRefreshWhileOneIsInFlightStartsNoParallelFetch() async throws {
        // The panel's open and its refresh button both force: the second waits, then one
        // follow-up runs after the first fetch, never alongside it.
        let gated = GatedLimits(limitSnapshot(.claude, fiveHour: 0.3, weekly: 0.42))
        let sut = store(claudeLimits: gated)
        let first = Task { await sut.refreshLimits(force: true) }
        try await waitUntil { gated.forces.count == 1 }

        let second = Task { await sut.refreshLimits(force: true) }
        try await waitOnMain { sut.limitsFetchWaiters == 1 }
        #expect(gated.forces == [true])

        gated.open()
        await first.value
        await second.value
        #expect(gated.forces == [true, true])
        #expect(sut.limitsFetchWaiters == 0)
    }

    // MARK: Inert

    @Test func anInertStoreTouchesNoSource() async throws {
        let accounts = CountingAccounts()
        let sut = store(interval: .milliseconds(10), accounts: accounts, isInert: true)
        sut.start()
        await sut.refreshLimits(force: true)
        await sut.refresh()
        try await Task.sleep(for: .milliseconds(50))
        sut.stop()

        #expect(claudeLimits.forces.isEmpty)
        #expect(codexLimits.forces.isEmpty)
        #expect(claudeCollector.calls == 0)
        #expect(codexCollector.calls == 0)
        #expect(accounts.count == 0)
        #expect(samples.recorded.isEmpty)
    }

    @Test func theInertFactoryHasNoSources() async throws {
        let sut = UsageStore.inert()
        #expect(sut.isInert)
        await sut.refreshLimits(force: true)
        #expect(sut.state.advice == nil)
    }

    // MARK: Loop

    @Test func theLoopTicksUntilStopped() async throws {
        let sut = store(interval: .milliseconds(20))
        sut.start()
        sut.start()
        let collector = claudeCollector
        try await waitUntil { collector.calls >= 3 }
        sut.stop()
        try await Task.sleep(for: .milliseconds(60))
        let calls = claudeCollector.calls
        try await Task.sleep(for: .milliseconds(100))
        #expect(claudeCollector.calls == calls)
        #expect(claudeLimits.forces == [false])
    }
}

/// `waitUntil` for main-actor state.
@MainActor
private func waitOnMain(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else {
            Issue.record("Timed out waiting for a main-actor condition")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
