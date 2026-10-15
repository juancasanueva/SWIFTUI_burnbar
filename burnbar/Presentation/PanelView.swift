//
//  PanelView.swift
//  burnbar
//

import SwiftUI

/// Placeholder menu bar label until the heat strip lands.
struct MenuBarLabel: View {
    var body: some View {
        Text("BURNBAR")
    }
}

/// Placeholder cockpit panel until the provider cards land.
struct PanelView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("burnbar")
                .font(.headline)
            Text("Collecting usage…")
                .foregroundStyle(.secondary)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 320)
    }
}

#Preview {
    PanelView()
}
