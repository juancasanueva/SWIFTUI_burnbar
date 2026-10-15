//
//  PanelView.swift
//  burnbar
//

import SwiftUI

/// Minimal cockpit panel until the provider cards land: per-provider limits, the advice chip
/// (click to dismiss until it gets worse) and status text. Opening it forces a limits refresh.
struct PanelView: View {
    let store: UsageStore

    var body: some View {
        let state = store.state
        VStack(alignment: .leading, spacing: 10) {
            Text("burnbar")
                .font(.headline)
            ForEach(state.providers) { provider in
                ProviderStatusRow(provider: provider)
            }
            if let advice = state.visibleAdvice {
                Button(action: store.dismissAdvice) {
                    Text(advice.text)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color(LanePalette.amber)))
                }
                .buttonStyle(.plain)
                .help("Dismiss until the advice gets worse")
                .accessibilityHint("Dismisses the advice until it gets worse")
            }
            if let status = state.statusText {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                if let updated = state.updatedAt {
                    Text("Updated \(updated, format: .dateTime.hour().minute().second())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding()
        .frame(width: 320)
        .task { await store.refreshLimits(force: true) }
    }
}

private struct ProviderStatusRow: View {
    let provider: ProviderState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(provider.provider.title)
                    .font(.subheadline.weight(.semibold))
                if provider.isStale {
                    Text("stale")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Text("5h \(Self.percent(provider.fiveHour))  ·  week \(Self.percent(provider.weekly))")
                    .font(.caption.monospacedDigit())
            }
            HStack {
                Text("\(provider.lane.heat.formatted()) tokens · \(provider.lane.turns) turns")
                Spacer()
                if let account = provider.account?.label {
                    Text(account)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private static func percent(_ pace: Pace?) -> String {
        pace.map { "\(Int(($0.percent * 100).rounded()))%" } ?? "—"
    }
}
