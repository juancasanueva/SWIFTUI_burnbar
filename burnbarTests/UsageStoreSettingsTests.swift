//
//  UsageStoreSettingsTests.swift
//  burnbarTests
//
//  How persisted settings shape the store's published state.
//

import Foundation
import Testing
@testable import burnbar

@MainActor
final class UsageStoreSettingsTests {
    private let clock = TestClock(now)
    private let claudeCollector = StubCollector()
    private let codexCollector = StubCollector()
    private let claudeLimits = StubLimits()
    private let codexLimits = StubLimits()
    private let defaults: UserDefaults
    private let suiteName: String
    private let settings: BurnbarSettings

    init() {
        (defaults, suiteName) = makeTestDefaults()
        settings = BurnbarSettings(defaults: defaults)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    private func store() -> UsageStore {
        let clock = clock
        return UsageStore(
            collectors: [.claude: claudeCollector, .codex: codexCollector],
            limits: [.claude: claudeLimits, .codex: codexLimits],
            samples: StubSampleStore(),
            accounts: StubAccounts(),
            defaults: defaults,
            settings: settings,
            now: { clock.now }
        )
    }

    /// Claude over its weekly pace and burning now; Codex well under pace.
    private func seedOverAndBanked() {
        claudeCollector.set([event(.claude, at: -600, input: 500, output: 100)])
        codexCollector.set([event(.codex, at: -600, input: 50)])
        claudeLimits.set(limitSnapshot(.claude, fiveHour: 0.3, weekly: 0.8))
        codexLimits.set(limitSnapshot(.codex, fiveHour: 0.1, weekly: 0.2))
    }

    // MARK: Providers

    @Test func aDisabledProviderHasNoCardLaneOrAdvice() async {
        seedOverAndBanked()
        settings.setEnabled(.codex, false)
        let sut = store()
        await sut.refresh()

        let state = sut.state
        #expect(state.providers.map(\.provider) == [.claude])
        #expect(state.cards(now: now).map(\.provider) == [.claude])
        #expect(state.summary.lanes[.codex] == nil)
        #expect(state.advice != .useNext(.codex))
        #expect(codexCollector.calls == 0)
        #expect(codexLimits.forces.isEmpty)
    }

    @Test func reEnablingAProviderBringsItBackWithoutRestart() async {
        seedOverAndBanked()
        settings.setEnabled(.codex, false)
        let sut = store()
        await sut.refresh()

        settings.setEnabled(.codex, true)
        await sut.settingsDidChange()
        await sut.refreshLimitsIfDue()

        #expect(sut.state.providers.map(\.provider) == [.claude, .codex])
        #expect(sut.state.summary.lane(.codex).heat == 50)
        #expect(sut.state.advice == .useNext(.codex))
    }

    @Test func claudeLimitsAreNotReadWhenTurnedOff() async throws {
        seedOverAndBanked()
        settings.readClaudeLimits = false
        let sut = store()
        await sut.refresh()

        #expect(claudeLimits.forces.isEmpty)
        let claude = try #require(sut.state.provider(.claude))
        #expect(claude.limits.isEmpty)
        #expect(claude.status == nil)
        #expect(claude.lane.heat == 600)
    }

    @Test func turningClaudeLimitsOffDropsTheKnownOnes() async throws {
        seedOverAndBanked()
        let sut = store()
        await sut.refresh()
        settings.readClaudeLimits = false
        await sut.settingsDidChange()
        #expect(try #require(sut.state.provider(.claude)).limits.isEmpty)
    }

    @Test func accountNamesAreHiddenWhenTurnedOff() async {
        seedOverAndBanked()
        let sut = store()
        await sut.refresh()
        #expect(sut.state.cards(now: now).first?.accountLabel == "dev@example.com")

        settings.showAccountNames = false
        await sut.settingsDidChange()
        #expect(sut.state.cards(now: now).allSatisfy { $0.accountLabel == nil })
    }

    // MARK: Strip

    @Test func theStripWindowAndCellCountShapeTheGrid() async {
        claudeCollector.set([
            event(.claude, at: -50 * minute, input: 100),
            event(.claude, at: -70 * minute, input: 1000),
        ])
        settings.stripWindow = .oneHour
        settings.cellsPerLane = .eight
        let sut = store()
        await sut.collectUsage()

        let summary = sut.state.summary
        #expect(summary.bucketStarts.count == 8)
        #expect(summary.lane(.claude).buckets.count == 8)
        #expect(summary.bucketStarts.last!.timeIntervalSince(summary.bucketStarts.first!) == 7 * 450)
        #expect(summary.lane(.claude).heat == 100)
        #expect(summary.lane(.codex).buckets.count == 8)
        #expect(sut.state.header.windowLabel == "1 h")
    }

    @Test func changingTheStripWindowRebucketsLive() async {
        claudeCollector.set([event(.claude, at: -20 * hour, input: 100)])
        let sut = store()
        await sut.collectUsage()
        #expect(sut.state.summary.lane(.claude).heat == 0)

        settings.stripWindow = .oneDay
        settings.cellsPerLane = .twentyFour
        await sut.settingsDidChange()
        #expect(sut.state.summary.bucketStarts.count == 24)
        #expect(sut.state.summary.lane(.claude).heat == 100)
        #expect(sut.state.header.windowLabel == "1 d")
    }

    // MARK: Intervals

    @Test func theLimitsRefreshIntervalIsReadLive() async {
        let sut = store()
        await sut.refreshLimitsIfDue()
        clock.advance(3 * minute)
        await sut.refreshLimitsIfDue()
        #expect(claudeLimits.forces.count == 1)

        settings.limitsRefreshInterval = .twoMinutes
        await sut.refreshLimitsIfDue()
        #expect(claudeLimits.forces.count == 2)
    }

    @Test func theCollectIntervalFollowsTheSetting() {
        let sut = store()
        #expect(sut.collectInterval == .seconds(5))
        settings.refreshInterval = .thirtySeconds
        #expect(sut.collectInterval == .seconds(30))
    }

    // MARK: Advice

    @Test func noSuggestionWhenSuggestNextSubIsOff() async {
        claudeCollector.set([])
        codexCollector.set([])
        claudeLimits.set(limitSnapshot(.claude, fiveHour: 0.1, weekly: 0.3))
        codexLimits.set(limitSnapshot(.codex, fiveHour: 0.1, weekly: 0.2))
        settings.suggestNextSub = false
        let sut = store()
        await sut.refresh()
        #expect(sut.state.advice == nil)
    }

    @Test func warningsStillShowWhenSuggestNextSubIsOff() async {
        seedOverAndBanked()
        settings.suggestNextSub = false
        let sut = store()
        await sut.refresh()
        guard case .rest(.claude, _) = sut.state.advice else {
            Issue.record("expected REST CLAUDE, got \(String(describing: sut.state.advice))")
            return
        }
    }

    // MARK: 5-hour windows

    @Test func fiveHourWindowsAreHiddenUnlessRunningOut() async throws {
        claudeLimits.set(limitSnapshot(.claude, fiveHour: 0.3, weekly: 0.4))
        codexLimits.set(limitSnapshot(.codex, fiveHour: 0.95, weekly: 0.2))
        let sut = store()
        await sut.refresh()

        let cards = sut.state.cards(now: now)
        let claude = try #require(cards.first { $0.provider == .claude })
        let codex = try #require(cards.first { $0.provider == .codex })
        #expect(claude.lines.map(\.label) == ["Weekly (7-day)"])
        #expect(codex.lines.map(\.label) == ["Session (5-hour)", "Weekly (7-day)"])
    }

    @Test func fiveHourWindowsShowWhenTurnedOn() async throws {
        claudeLimits.set(limitSnapshot(.claude, fiveHour: 0.3, weekly: 0.4))
        settings.showFiveHourWindows = true
        let sut = store()
        await sut.refresh()
        let claude = try #require(sut.state.cards(now: now).first { $0.provider == .claude })
        #expect(claude.lines.map(\.label) == ["Session (5-hour)", "Weekly (7-day)"])
    }

    // MARK: Warn me again

    @Test func warnMeAgainClearsTheDismissal() async {
        seedOverAndBanked()
        let sut = store()
        await sut.refresh()
        #expect(sut.state.dismissedAdviceCount == 0)

        sut.dismissAdvice()
        #expect(sut.state.visibleAdvice == nil)
        #expect(sut.state.dismissedAdviceCount == 1)

        sut.warnMeAgain()
        #expect(sut.state.visibleAdvice == .useNext(.codex))
        #expect(sut.state.dismissedAdviceCount == 0)
        #expect(!sut.state.hasDismissedAdvice)
        #expect(defaults.string(forKey: UsageStore.DefaultsKey.dismissedIdentity) == nil)
    }

    // MARK: Ember motion

    @Test func aStoredEmberMotionOffReachesThePublishedState() async {
        defaults.set(false, forKey: BurnbarSettings.Key.emberMotion)
        let sut = UsageStore(collectors: [:], limits: [:], samples: StubSampleStore(), accounts: StubAccounts(),
                             defaults: defaults, now: { now })
        await sut.collectUsage()
        #expect(sut.settings.emberMotion == false)
        #expect(sut.state.emberMotion == false)
    }

    @Test func togglingEmberMotionRepublishes() async {
        let sut = store()
        await sut.collectUsage()
        #expect(sut.state.emberMotion)

        settings.emberMotion = false
        await sut.settingsDidChange()
        #expect(sut.state.emberMotion == false)
        #expect(defaults.object(forKey: BurnbarSettings.Key.emberMotion) as? Bool == false)
    }

    // MARK: New-burn flashes

    @Test func aLaneFlashesWhenItsLatestBucketGrows() async {
        claudeCollector.set([event(.claude, at: -600, input: 500)])
        codexCollector.set([event(.codex, at: -600, input: 50)])
        let sut = store()
        await sut.collectUsage()
        #expect(sut.state.flashStarts.isEmpty)

        clock.advance(5)
        claudeCollector.set([event(.claude, at: -600, input: 500), event(.claude, at: 0, input: 200)])
        await sut.collectUsage()
        #expect(sut.state.flashStarts == [.claude: now.addingTimeInterval(5)])

        // Nothing new: the recorded start stays, no new lane flashes.
        clock.advance(5)
        await sut.collectUsage()
        #expect(sut.state.flashStarts == [.claude: now.addingTimeInterval(5)])
    }
}
