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

    init() {
        let settings = BurnbarSettings()
        let store = Self.isInert ? UsageStore.inert(settings: settings) : UsageStore.live(settings: settings)
        store.start()
        _store = State(initialValue: store)
        // Inert runs never touch the real login item.
        let loginItem: any LoginItemControlling = Self.isInert
            ? InMemoryLoginItem(isEnabled: settings.launchAtLogin) : SystemLoginItem()
        let launchAtLogin = LaunchAtLoginController(item: loginItem, settings: settings)
        launchAtLogin.sync()
        _launchAtLogin = State(initialValue: launchAtLogin)
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
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
