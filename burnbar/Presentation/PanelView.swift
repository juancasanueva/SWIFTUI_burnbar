//
//  PanelView.swift
//  burnbar
//

import SwiftUI

/// The cockpit panel's container: reads the store and hands plain view state to `CockpitView`.
/// Opening the panel forces a limits refresh, and so does the header's refresh button.
struct PanelView: View {
    let store: UsageStore

    @State private var isRefreshing = false

    var body: some View {
        let state = store.state
        CockpitView(
            header: state.header,
            advice: state.visibleAdvice?.text,
            cards: state.cards(now: .now),
            isRefreshing: isRefreshing,
            onRefresh: refresh,
            onDismissAdvice: store.dismissAdvice,
            onQuit: { NSApplication.shared.terminate(nil) }
        )
        .task { await store.refreshLimits(force: true) }
    }

    private func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            await store.refreshLimits(force: true)
            isRefreshing = false
        }
    }
}

/// The cockpit: header, the advice chip (click to dismiss until it gets worse), then one card per
/// provider, scrolling once taller than `maxScrollHeight`.
struct CockpitView: View {
    let header: CockpitHeader
    let advice: String?
    let cards: [ProviderCard]
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onDismissAdvice: () -> Void
    let onQuit: () -> Void

    static let width: CGFloat = 360
    static let maxScrollHeight: CGFloat = 600

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CockpitHeaderView(header: header, isRefreshing: isRefreshing, onRefresh: onRefresh, onQuit: onQuit)
            if let advice {
                AdviceChipButton(text: advice, action: onDismissAdvice)
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(cards) { ProviderCardView(card: $0) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: contentHeight > 0 ? min(contentHeight, Self.maxScrollHeight) : nil)
        }
        .padding(12)
        .frame(width: Self.width)
    }
}

/// The amber advice chip as a button that dismisses it.
struct AdviceChipButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption.weight(.heavy))
                .foregroundStyle(.black)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(LanePalette.amber)))
        }
        .buttonStyle(.plain)
        .help("Dismiss until the advice gets worse")
        .accessibilityLabel("Advice: \(text.lowercased())")
        .accessibilityHint("Dismisses the advice until it gets worse")
    }
}

/// Trailing-window totals, the update time, refresh and quit.
struct CockpitHeaderView: View {
    let header: CockpitHeader
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("burnbar")
                    .font(.headline)
                Text("\(header.tokensText) tokens · \(header.turns) turns · \(header.sessions) sessions (6 h)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let updated = header.updatedAt {
                    Text("Updated \(updated, format: .dateTime.hour().minute().second())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(isRefreshing)
            .help("Refresh limits")
            .accessibilityLabel(isRefreshing ? "Refreshing limits" : "Refresh limits")
            Button("Quit", action: onQuit)
                .keyboardShortcut("q")
        }
    }
}

#if DEBUG
#Preview("Cockpit") {
    CockpitView(header: CockpitPreview.header, advice: "USE CODEX NEXT", cards: CockpitPreview.cards,
                isRefreshing: false, onRefresh: {}, onDismissAdvice: {}, onQuit: {})
}

#Preview("Empty") {
    CockpitView(header: CockpitHeader(state: .empty), advice: nil, cards: UsageViewState.empty.cards(now: .now),
                isRefreshing: true, onRefresh: {}, onDismissAdvice: {}, onQuit: {})
}
#endif
