//
//  BurnbarSettingsTests.swift
//  burnbarTests
//

import Foundation
import Testing
@testable import burnbar

@MainActor
final class BurnbarSettingsTests {
    private let defaults: UserDefaults
    private let suiteName: String

    init() {
        (defaults, suiteName) = makeTestDefaults()
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    @Test func freshSettingsUseTheDefaults() {
        let sut = BurnbarSettings(defaults: defaults)
        #expect(sut.enabledProviders == [.claude, .codex])
        #expect(sut.showAccountNames)
        #expect(sut.readClaudeLimits)
        #expect(sut.stripWindow == .sixHours)
        #expect(sut.cellsPerLane == .twelve)
        #expect(sut.refreshInterval == .fiveSeconds)
        #expect(sut.limitsRefreshInterval == .fiveMinutes)
        #expect(sut.suggestNextSub)
        #expect(!sut.showFiveHourWindows)
        #expect(sut.theme == .dark)
        #expect(sut.headline == .budget)
        #expect(sut.glowWhen == .over)
        #expect(sut.emberMotion)
        #expect(!sut.launchAtLogin)
        #expect(sut.grid == .standard)
    }

    @Test func everySettingSurvivesARelaunch() {
        let sut = BurnbarSettings(defaults: defaults)
        sut.setEnabled(.codex, false)
        sut.showAccountNames = false
        sut.readClaudeLimits = false
        sut.stripWindow = .oneDay
        sut.cellsPerLane = .twentyFour
        sut.refreshInterval = .oneMinute
        sut.limitsRefreshInterval = .thirtyMinutes
        sut.suggestNextSub = false
        sut.showFiveHourWindows = true
        sut.theme = .system
        sut.headline = .tokens
        sut.glowWhen = .never
        sut.emberMotion = false
        sut.launchAtLogin = true

        let relaunched = BurnbarSettings(defaults: defaults)
        #expect(relaunched.enabledProviders == [.claude])
        #expect(!relaunched.isEnabled(.codex))
        #expect(!relaunched.showAccountNames)
        #expect(!relaunched.readClaudeLimits)
        #expect(relaunched.stripWindow == .oneDay)
        #expect(relaunched.cellsPerLane == .twentyFour)
        #expect(relaunched.refreshInterval == .oneMinute)
        #expect(relaunched.limitsRefreshInterval == .thirtyMinutes)
        #expect(!relaunched.suggestNextSub)
        #expect(relaunched.showFiveHourWindows)
        #expect(relaunched.theme == .system)
        #expect(relaunched.headline == .tokens)
        #expect(relaunched.glowWhen == .never)
        #expect(!relaunched.emberMotion)
        #expect(relaunched.launchAtLogin)
        #expect(relaunched.grid == StripGrid(window: 24 * hour, cells: 24))
    }

    @Test func bothProvidersCanBeDisabledAndStayDisabled() {
        let sut = BurnbarSettings(defaults: defaults)
        sut.setEnabled(.claude, false)
        sut.setEnabled(.codex, false)
        #expect(BurnbarSettings(defaults: defaults).enabledProviders.isEmpty)
    }

    @Test func unknownStoredValuesFallBackToTheDefaults() {
        defaults.set("2w", forKey: BurnbarSettings.Key.stripWindow)
        defaults.set(7, forKey: BurnbarSettings.Key.cellsPerLane)
        defaults.set("neon", forKey: BurnbarSettings.Key.theme)
        let sut = BurnbarSettings(defaults: defaults)
        #expect(sut.stripWindow == .sixHours)
        #expect(sut.cellsPerLane == .twelve)
        #expect(sut.theme == .dark)
    }

    @Test(arguments: StripWindow.allCases)
    func theLongestStripWindowCoversEveryOther(window: StripWindow) {
        #expect(window.duration <= StripWindow.longest.duration)
    }

    @Test func intervalsConvertToDurations() {
        #expect(RefreshInterval.tenSeconds.duration == .seconds(10))
        #expect(LimitsRefreshInterval.twoMinutes.seconds == 120)
        #expect(StripWindow.threeHours.duration == 3 * hour)
    }
}
