//
//  burnbarApp.swift
//  burnbar
//

import SwiftUI

/// Menu-bar-only entry point (LSUIElement): no windows, one window-style extra.
@main
struct burnbarApp: App {
    @State private var store: UsageStore

    init() {
        let store = Self.isInert ? UsageStore.inert() : UsageStore.live()
        store.start()
        _store = State(initialValue: store)
    }

    /// Hosted unit tests launch the app, and so can UI tests (with `BURNBAR_INERT=1`): the
    /// store then has no sources and ignores every refresh, so nothing reads the Keychain, the
    /// network, account files or real transcripts (the panel's refresh on open included).
    private static var isInert: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["BURNBAR_INERT"] == "1"
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
