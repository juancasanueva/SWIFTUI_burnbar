//
//  SetupDisplayTests.swift
//  burnbarTests
//
//  The setup screen's pure decisions: subscription status captions, the warnings caption,
//  option labels, and launch at login staying in step with the real login item.
//

import Foundation
import Testing
@testable import burnbar

struct SetupDisplayTests {
    private func card(_ rows: [LimitRow], provider: Provider = .claude, hasError: Bool = false) -> ProviderCard {
        let limits = rows.map { row in
            let pace = PaceCalculator.pace(for: row, samples: [], now: now)
            return LimitRowState(row: pace?.row ?? row, pace: pace)
        }
        let state = ProviderState(provider: provider, lane: .empty(provider), limits: limits, measuredAt: now,
                                  status: nil, isStale: false, hasError: hasError, account: nil)
        return ProviderCard(state: state, now: now)
    }

    // MARK: Subscription captions

    @Test func bankedSubscriptionShowsItsBankedShare() {
        let caption = SubscriptionRow.caption(card: card([row(percent: 0.1, elapsed: 0.5)]), isEnabled: true)
        #expect(caption == "Banked 40%")
    }

    @Test func evenSpendIsOnPace() {
        #expect(SubscriptionRow.caption(card: card([row(percent: 0.5, elapsed: 0.5)]), isEnabled: true) == "On pace")
    }

    @Test func aSpentBudgetWaitsForTheReset() {
        let caption = SubscriptionRow.caption(card: card([row(percent: 1, elapsed: 0.5)]), isEnabled: true)
        #expect(caption == "Spent until it resets")
    }

    @Test func overPaceSaysWhenToComeBackInSentenceCase() {
        let caption = SubscriptionRow.caption(card: card([row(percent: 0.8, elapsed: 0.5)]), isEnabled: true)
        #expect(caption.hasPrefix("Come back in ") || caption == "Back at the reset")
        #expect(caption != caption.uppercased())
    }

    @Test func noLimitsMeansNoPlanReading() {
        #expect(SubscriptionRow.caption(card: card([]), isEnabled: true) == "No plan reading")
    }

    @Test func aDisabledSubscriptionIsTurnedOff() {
        #expect(SubscriptionRow.caption(card: card([row(percent: 0.1, elapsed: 0.5)]), isEnabled: false) == "Turned off")
        #expect(SubscriptionRow.caption(card: nil, isEnabled: false) == "Turned off")
    }

    @Test func rowsCoverEveryProviderAndMatchTheirCards() {
        let rows = SubscriptionRow.rows(cards: [card([row(percent: 0.5, elapsed: 0.5)], provider: .codex)],
                                        enabled: [.codex])
        #expect(rows.map(\.provider) == Provider.allCases)
        #expect(rows.first { $0.provider == .codex }?.caption == "On pace")
        #expect(rows.first { $0.provider == .codex }?.isEnabled == true)
        #expect(rows.first { $0.provider == .claude }?.caption == "Turned off")
        #expect(rows.first { $0.provider == .claude }?.name == "Claude")
    }

    // MARK: Warnings

    @Test(arguments: [(0, "nothing dismissed"), (1, "1 dismissed"), (3, "3 dismissed")])
    func warningsCaptionCountsDismissals(count: Int, expected: String) {
        #expect(SetupDisplay.warningsCaption(dismissedCount: count) == expected)
    }

    // MARK: Option labels

    @Test func optionLabelsMatchTheReference() {
        #expect(StripWindow.allCases.map(\.label) == ["1h", "3h", "6h", "12h", "1d"])
        #expect(CellsPerLane.allCases.map(\.label) == ["8", "12", "18", "24"])
        #expect(RefreshInterval.allCases.map(\.label) == ["5s", "10s", "30s", "60s"])
        #expect(LimitsRefreshInterval.allCases.map(\.label) == ["2m", "5m", "10m", "30m"])
        #expect(ThemePreference.allCases.map(\.label) == ["Dark", "Light", "System"])
        #expect(HeadlineMode.allCases.map(\.label) == ["Budget", "Tokens"])
        #expect(GlowWhen.allCases.map(\.label) == ["Over", "Burning", "Spent", "Never"])
    }
}

/// A login item double: a status, and an optional error every change throws.
@MainActor
final class FakeLoginItem: LoginItemControlling {
    var status: LoginItemStatus
    var failure: (any Error)?
    /// What the fake becomes after a successful register.
    var statusAfterRegister: LoginItemStatus = .enabled
    private(set) var calls: [Bool] = []

    init(status: LoginItemStatus = .disabled, failure: (any Error)? = nil) {
        self.status = status
        self.failure = failure
    }

    func setEnabled(_ isEnabled: Bool) throws {
        calls.append(isEnabled)
        if let failure { throw failure }
        status = isEnabled ? statusAfterRegister : .disabled
    }
}

private struct LoginItemFailure: LocalizedError {
    var errorDescription: String? { "Operation not permitted" }
}

@MainActor
struct LaunchAtLoginControllerTests {
    private func settings(launchAtLogin: Bool = false) -> BurnbarSettings {
        let defaults = UserDefaults(suiteName: "LaunchAtLoginControllerTests.\(UUID().uuidString)")!
        let settings = BurnbarSettings(defaults: defaults)
        settings.launchAtLogin = launchAtLogin
        return settings
    }

    @Test func syncReflectsTheRealLoginItem() {
        let s = settings(launchAtLogin: false)
        let controller = LaunchAtLoginController(item: FakeLoginItem(status: .enabled), settings: s)
        controller.sync()
        #expect(s.launchAtLogin)

        let off = settings(launchAtLogin: true)
        LaunchAtLoginController(item: FakeLoginItem(status: .disabled), settings: off).sync()
        #expect(!off.launchAtLogin)
    }

    @Test func turningOnRegistersTheLoginItem() {
        let s = settings()
        let item = FakeLoginItem()
        let controller = LaunchAtLoginController(item: item, settings: s)
        controller.setEnabled(true)
        #expect(item.calls == [true])
        #expect(s.launchAtLogin)
        #expect(controller.message == nil)
    }

    @Test func turningOffUnregistersTheLoginItem() {
        let s = settings(launchAtLogin: true)
        let item = FakeLoginItem(status: .enabled)
        LaunchAtLoginController(item: item, settings: s).setEnabled(false)
        #expect(item.calls == [false])
        #expect(!s.launchAtLogin)
    }

    @Test func aFailedChangeRevertsTheToggleAndSaysWhy() {
        let s = settings()
        let controller = LaunchAtLoginController(item: FakeLoginItem(failure: LoginItemFailure()), settings: s)
        controller.setEnabled(true)
        #expect(!s.launchAtLogin)
        #expect(controller.message == "Couldn't change login item: Operation not permitted")
    }

    @Test func aSuccessfulChangeClearsAnEarlierError() {
        let s = settings()
        let item = FakeLoginItem(failure: LoginItemFailure())
        let controller = LaunchAtLoginController(item: item, settings: s)
        controller.setEnabled(true)
        item.failure = nil
        controller.setEnabled(true)
        #expect(s.launchAtLogin)
        #expect(controller.message == nil)
    }

    @Test func awaitingApprovalStaysOffAndPointsToSystemSettings() {
        let s = settings()
        let item = FakeLoginItem()
        item.statusAfterRegister = .requiresApproval
        let controller = LaunchAtLoginController(item: item, settings: s)
        controller.setEnabled(true)
        #expect(!s.launchAtLogin)
        #expect(controller.message == "Allow Burnbar in System Settings › General › Login Items.")
    }
}
