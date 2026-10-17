//
//  SetupUpdatesTests.swift
//  burnbarTests
//
//  The setup screen's "Updates" group: the version line, the command's enablement, the
//  last-checked caption and the automatic-checks binding, all over `FakeAppUpdater`.
//

import Foundation
import SwiftUI
import Testing
@testable import burnbar

@MainActor
struct SetupUpdatesTests {
    private static let now = Date(timeIntervalSince1970: 1_787_000_000)

    @Test func theVersionLineNamesTheMarketingVersionAndTheBuild() {
        let info: [String: Any] = ["CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "42"]
        #expect(SetupUpdates.versionLine(bundleInfo: info) == "Burnbar 1.2.0 (42)")
    }

    /// Missing values are left out rather than invented.
    @Test func theVersionLineLeavesOutWhatTheBundleDoesNotSay() {
        #expect(SetupUpdates.versionLine(bundleInfo: ["CFBundleShortVersionString": "1.2.0"]) == "Burnbar 1.2.0")
        #expect(SetupUpdates.versionLine(bundleInfo: [:]) == "Burnbar")
    }

    /// The running host's line, from its real Info.plist.
    @Test func theHostVersionLineReadsTheBundle() throws {
        let info = try #require(Bundle.main.infoDictionary)
        let short = try #require(info["CFBundleShortVersionString"] as? String)
        let build = try #require(info["CFBundleVersion"] as? String)
        #expect(SetupUpdates.versionLine(bundleInfo: info) == "Burnbar \(short) (\(build))")
    }

    @Test(arguments: [true, false])
    func theCheckRowFollowsWhetherACheckCanRun(canCheck: Bool) {
        let updater = FakeAppUpdater(canCheckForUpdates: canCheck)
        let updates = SetupUpdates(updater: updater, bundleInfo: [:], now: Self.now)
        #expect(updates.canCheck == canCheck)
    }

    @Test func theCaptionSaysNeverCheckedUntilACheckIsRecorded() {
        let updater = FakeAppUpdater()
        #expect(SetupUpdates(updater: updater, bundleInfo: [:], now: Self.now).lastChecked == "Never checked")

        updater.recordCheck(at: Self.now.addingTimeInterval(-3600))
        let caption = SetupUpdates(updater: updater, bundleInfo: [:], now: Self.now).lastChecked
        #expect(caption == UpdateCheckPresentation(lastCheck: Self.now.addingTimeInterval(-3600), now: Self.now).label)
        #expect(caption.hasPrefix("Last checked "))
    }

    /// The setup toggle reads and writes the updater, which persists the preference.
    @Test func theAutomaticChecksBindingWritesTheUpdater() {
        let (defaults, name) = makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = BurnbarSettings(defaults: defaults)
        let launchAtLogin = LaunchAtLoginController(item: InMemoryLoginItem(isEnabled: false), settings: settings)
        let updater = FakeAppUpdater(automaticallyChecksForUpdates: false)

        let controls = SetupControls(settings: settings, launchAtLogin: launchAtLogin, updater: updater)

        #expect(controls.automaticUpdateChecks.wrappedValue == false)
        controls.automaticUpdateChecks.wrappedValue = true
        #expect(updater.automaticallyChecksForUpdates)
        #expect(updater.automaticWriteCount == 1)
    }
}
