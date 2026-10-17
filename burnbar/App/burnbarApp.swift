//
//  burnbarApp.swift
//  burnbar
//

import SwiftUI

/// Menu-bar-only entry point (LSUIElement): no windows, one window-style extra.
@main
struct burnbarApp: App {
    @State private var store: UsageStore
    @State private var launchAtLogin: LaunchAtLoginController
    @State private var clock: StripAnimationClock
    /// The one updater: every update surface observes this instance. Typed as the port.
    @State private var updater: any AppUpdating

    init() {
        let settings = BurnbarSettings()
        let store = Self.isInert ? UsageStore.inert(settings: settings) : UsageStore.live(settings: settings)
        store.start()
        _store = State(initialValue: store)
        // The strip's motion; inert runs keep it still, with no task.
        let clock = StripAnimationClock()
        if !Self.isInert { clock.follow(store) }
        _clock = State(initialValue: clock)
        // Inert runs never touch the real login item.
        let loginItem: any LoginItemControlling = Self.isInert
            ? InMemoryLoginItem(isEnabled: settings.launchAtLogin) : SystemLoginItem()
        let launchAtLogin = LaunchAtLoginController(item: loginItem, settings: settings)
        launchAtLogin.sync()
        _launchAtLogin = State(initialValue: launchAtLogin)
        _updater = State(initialValue: Self.makeUpdater(isInert: Self.isInert))
    }

    /// Inert runs never start Sparkle: starting it from a test run would reach the feed, write
    /// the developer's real automatic-check preference and let Sparkle open its own window.
    /// Building the real one applies the app's persisted preference before the updater starts.
    static func makeUpdater(isInert: Bool) -> any AppUpdating {
        isInert ? InMemoryAppUpdater()
            : SparkleUpdateChecker(automaticChecks: AutomaticUpdateChecks(defaults: .standard))
    }

    /// Hosted unit tests launch the app, and so can UI tests (with `BURNBAR_INERT=1`): the
    /// store then has no sources and ignores every refresh, so nothing reads the Keychain, the
    /// network, account files or real transcripts (the panel's refresh on open included), and the login item is an in-memory stand-in.
    private static var isInert: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["BURNBAR_INERT"] == "1"
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store, launchAtLogin: launchAtLogin)
        } label: {
            MenuBarLabel(store: store, clock: clock)
        }
        .menuBarExtraStyle(.window)
    }
}
