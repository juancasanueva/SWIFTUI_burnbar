//
//  burnbarApp.swift
//  burnbar
//

import SwiftUI

/// Menu-bar-only entry point (LSUIElement): no windows, one window-style extra.
@main
struct burnbarApp: App {
    var body: some Scene {
        MenuBarExtra {
            PanelView()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
    }
}
