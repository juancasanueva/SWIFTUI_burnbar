//
//  PanelView.swift
//  burnbar
//

import SwiftUI

/// Which screen the panel shows.
enum CockpitScreen: Hashable {
    case cockpit, setup
}

/// The panel's container: reads the store and settings and hands plain values and closures to
/// `CockpitView` (or `SetupView`, which also reflects the real login item when it opens). Opening the panel forces a limits refresh, and so does
/// the header's refresh button. The theme setting forces the panel's colour scheme.
struct PanelView: View {
    let store: UsageStore
    let launchAtLogin: LaunchAtLoginController

    @State private var isRefreshing = false
    @State private var screen: CockpitScreen = .cockpit

    var body: some View {
        let settings = store.settings
        Group {
            switch screen {
            case .cockpit:
                let state = store.state
                let cards = state.cards(now: .now)
                CockpitView(
                    header: state.header,
                    advice: state.visibleAdvice.map { AdviceBanner(advice: $0, cards: cards) },
                    cards: cards,
                    headline: settings.headline,
                    glowWhen: settings.glowWhen,
                    isRefreshing: isRefreshing,
                    onRefresh: refresh,
                    onDismissAdvice: store.dismissAdvice,
                    onToggleHeadline: toggleHeadline,
                    onOpenSetup: { screen = .setup },
                    onQuit: quit
                )
            case .setup:
                let state = store.state
                SetupView(
                    header: state.header,
                    subscriptions: SubscriptionRow.rows(cards: state.cards(now: .now), enabled: settings.enabledProviders),
                    warningsCaption: SetupDisplay.warningsCaption(dismissedCount: state.dismissedAdviceCount),
                    canWarnAgain: state.hasDismissedAdvice,
                    loginItemMessage: launchAtLogin.message,
                    controls: SetupControls(settings: settings, launchAtLogin: launchAtLogin),
                    isRefreshing: isRefreshing,
                    onSetEnabled: settings.setEnabled,
                    onWarnMeAgain: store.warnMeAgain,
                    onRefresh: refresh,
                    onDone: { screen = .cockpit },
                    onQuit: quit
                )
                .onAppear(perform: launchAtLogin.sync)
            }
        }
        .preferredColorScheme(settings.theme.colorScheme)
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

    private func toggleHeadline() {
        store.settings.headline = store.settings.headline.toggled
    }

    private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

/// The wide cockpit: header, the advice banner (click to dismiss until it gets worse), one
/// column per provider card, then the footer. Scrolls once taller than `maxScrollHeight`.
struct CockpitView: View {
    let header: CockpitHeader
    let advice: AdviceBanner?
    let cards: [ProviderCard]
    let headline: HeadlineMode
    let glowWhen: GlowWhen
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onDismissAdvice: () -> Void
    let onToggleHeadline: () -> Void
    let onOpenSetup: () -> Void
    let onQuit: () -> Void

    static let columnWidth: CGFloat = 400
    static let spacing: CGFloat = 10
    static let padding: CGFloat = 12
    static let maxScrollHeight: CGFloat = 760

    /// Panel width for `columns` cards (at least one column, for the empty state).
    static func width(columns: Int) -> CGFloat {
        let n = CGFloat(max(columns, 1))
        return n * columnWidth + (n - 1) * spacing + 2 * padding
    }

    @State private var contentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Self.spacing) {
            CockpitHeaderView(header: header, isRefreshing: isRefreshing, onToggleSetup: onOpenSetup,
                              onRefresh: onRefresh, onQuit: onQuit)
            if let advice {
                AdviceBannerButton(banner: advice, action: onDismissAdvice)
            }
            ScrollView {
                columns
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: contentHeight > 0 ? min(contentHeight, Self.maxScrollHeight) : nil)
            CockpitFooter(updatedAt: header.updatedAt)
        }
        .padding(Self.padding)
        .frame(width: Self.width(columns: cards.count))
        .cockpitChrome()
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            if cards.isEmpty {
                Text("No subscriptions enabled — turn one on in SETUP")
                    .font(.system(size: 12))
                    .padding(12)
                    .frame(width: Self.columnWidth, alignment: .leading)
                    .cockpitBox()
            }
            ForEach(cards) { card in
                ProviderCardView(card: card, headline: card.headline(headline, windowLabel: header.windowLabel),
                                 glow: CardGlow.glow(for: card, when: glowWhen), windowLabel: header.windowLabel,
                                 window: header.window, onToggleHeadline: onToggleHeadline)
                    .frame(width: Self.columnWidth)
            }
        }
        // Room for the glow, which the scroll view would otherwise clip.
        .padding(.vertical, 6)
    }
}

/// The advice as a full-width box tinted with the advised provider's lane; clicking dismisses it.
struct AdviceBannerButton: View {
    let banner: AdviceBanner
    let action: () -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        let tint = banner.provider.map(palette.lane) ?? palette.bad
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Text(banner.title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(tint)
                if let detail = banner.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.13)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(tint.opacity(0.35), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Dismiss until the advice gets worse")
        .accessibilityLabel("Advice: \(banner.title.lowercased())" + (banner.detail.map { ", \($0)" } ?? ""))
        .accessibilityHint("Dismisses the advice until it gets worse")
    }
}

/// Wordmark and trailing-window totals; SETUP (DONE while setup is open, Esc too), refresh and quit.
struct CockpitHeaderView: View {
    let header: CockpitHeader
    var isSetupOpen = false
    let isRefreshing: Bool
    let onToggleSetup: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("BURN BAR")
                    .font(.system(size: 14, weight: .heavy))
                Text("\(header.tokensText) tokens · \(header.turns) turns · \(header.sessions) sessions · last \(header.windowLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button(isSetupOpen ? "DONE" : "SETUP", action: onToggleSetup)
                .buttonStyle(CockpitTextButtonStyle())
                .keyboardShortcut(isSetupOpen ? .cancelAction : KeyboardShortcut(","))
                .accessibilityLabel(isSetupOpen ? "Done" : "Setup")
                .accessibilityHint(isSetupOpen ? "Returns to the cockpit" : "Opens the settings")
            CockpitIconButton(systemImage: "arrow.clockwise",
                              label: isRefreshing ? "Refreshing limits" : "Refresh limits", action: onRefresh)
                .disabled(isRefreshing)
            CockpitIconButton(systemImage: "power", label: "Quit Burn Bar", action: onQuit)
                .keyboardShortcut("q")
        }
    }
}

/// Credits on the left, the last update on the right.
struct CockpitFooter: View {
    let updatedAt: Date?

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        HStack {
            Text("Burn Bar for macOS · a Mac port of Burn Bar by nixfred")
            Spacer()
            if let updatedAt {
                Text("updated \(updatedAt.formatted(.dateTime.hour().minute()))")
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(palette.secondary)
    }
}

#if DEBUG
#Preview("Cockpit") {
    CockpitView(header: CockpitPreview.header,
                advice: CockpitPreview.viewState.visibleAdvice.map { AdviceBanner(advice: $0, cards: CockpitPreview.cards) },
                cards: CockpitPreview.cards, headline: .budget, glowWhen: .over, isRefreshing: false,
                onRefresh: {}, onDismissAdvice: {}, onToggleHeadline: {}, onOpenSetup: {}, onQuit: {})
}

#Preview("Tokens, light") {
    CockpitView(header: CockpitPreview.header, advice: nil, cards: CockpitPreview.cards, headline: .tokens,
                glowWhen: .burning, isRefreshing: false,
                onRefresh: {}, onDismissAdvice: {}, onToggleHeadline: {}, onOpenSetup: {}, onQuit: {})
        .preferredColorScheme(.light)
}

#Preview("Empty") {
    CockpitView(header: CockpitHeader(state: .empty), advice: nil, cards: [], headline: .budget, glowWhen: .over,
                isRefreshing: true, onRefresh: {}, onDismissAdvice: {}, onToggleHeadline: {}, onOpenSetup: {}, onQuit: {})
}
#endif
