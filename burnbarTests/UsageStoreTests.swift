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

    private func store(interval: Duration = .seconds(5)) -> UsageStore {
        let clock = clock
        return UsageStore(
            collectors: [.claude: claudeCollector, .codex: codexCollector],
            limits: [.claude: claudeLimits, .codex: codexLimits],
            samples: samples,
            accounts: StubAccounts(),
            defaults: defaults,
            collectInterval: interval,
            now: { clock.now }
        )
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
        #expect(defaults.string(forKey: UsageStore.DefaultsKey.dismissedAdvice) == "USE CODEX NEXT")
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

    @Test func oldLimitsAreStaleAndPassedResetsAreUnknown() async throws {
        let measured = now.addingTimeInterval(-1000)
        let passed = LimitRow(label: "Session (5-hour)", percent: 0.5, resetsAt: now.addingTimeInterval(-1), windowDuration: fiveHours)
        codexLimits.set(LimitSnapshot(provider: .codex, rows: [passed], measuredAt: measured))
        let sut = store()
        await sut.refresh()
        let codex = try #require(sut.state.provider(.codex))
        #expect(codex.isStale)
        #expect(codex.limits.count == 1)
        #expect(codex.limits[0].pace == nil)
        #expect(codex.fiveHour == nil)
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
