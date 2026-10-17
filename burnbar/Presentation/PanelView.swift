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
    /// The system appearance, read above the override so "System" follows it.
    @Environment(\.colorScheme) private var systemColorScheme

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
        // A MenuBarExtra window ignores `preferredColorScheme`, so the scheme is injected directly.
        .environment(\.colorScheme, settings.theme.resolved(system: systemColorScheme))
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
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 16
    static let maxScrollHeight: CGFloat = 760

    /// Panel width for `columns` cards (at least one column, for the empty state).
    static func width(columns: Int) -> CGFloat {
        let n = CGFloat(max(columns, 1))
        return n * columnWidth + (n - 1) * spacing + 2 * padding
    }

    /// The footer's how-to-read line.
    static func hint(glowWhen: GlowWhen) -> String {
        let glow = glowWhen == .never ? "cards never glow (SETUP)" : "a card glows for: \(glowWhen.phrase) (SETUP)"
        return "the dashed diagonal is an even spend: a line above it is over budget · click a headline to flip budget and tokens · \(glow)"
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
            CockpitFooter(updatedAt: header.updatedAt, hint: Self.hint(glowWhen: glowWhen))
        }
        .padding(Self.padding)
        .frame(width: Self.width(columns: cards.count))
        .cockpitChrome()
    }

    private var columns: some View {
        HStack(alignment: .top, spacing: Self.spacing) {
            if cards.isEmpty {
                Text("no subscriptions enabled · turn one on in SETUP")
                    .font(.system(size: 11, design: .monospaced))
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
        .padding(.vertical, 8)
    }
}

/// The advice as one full-width bordered row tinted with the advised provider's lane:
/// "▶ USE CODEX NEXT" in tracked caps, the details inline. Clicking dismisses it.
struct AdviceBannerButton: View {
    let banner: AdviceBanner
    let action: () -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        let tint = banner.provider.map(palette.lane) ?? palette.bad
        let shape = RoundedRectangle(cornerRadius: 3)
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("▶")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(tint)
                Text(banner.title.uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(tint)
                    .layoutPriority(1)
                if let detail = banner.detail {
                    Text(detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.primary.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(tint.opacity(0.09)))
            .overlay(shape.strokeBorder(tint.opacity(0.45), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Dismiss until the advice gets worse")
        .accessibilityLabel("Advice: \(banner.title.lowercased())" + (banner.detail.map { ", \($0)" } ?? ""))
        .accessibilityHint("Dismisses the advice until it gets worse")
    }
}

/// A flame and the trailing-window total in orange, the tracked meta line beside it; SETUP
/// (DONE while setup is open, Esc too), refresh and a quiet quit on the right.
struct CockpitHeaderView: View {
    let header: CockpitHeader
    var isSetupOpen = false
    let isRefreshing: Bool
    let onToggleSetup: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16))
                        .accessibilityHidden(true)
                    Text(header.tokensText)
                        .font(.system(size: 24, weight: .medium, design: .monospaced))
                }
                Text("tokens burned · last \(header.windowLabel) · \(header.turns) turns · \(header.sessions) sessions".uppercased())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(palette.accent)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(isSetupOpen ? "DONE" : "SETUP", action: onToggleSetup)
                .buttonStyle(CockpitTextButtonStyle())
                .keyboardShortcut(isSetupOpen ? .cancelAction : KeyboardShortcut(","))
                .accessibilityLabel(isSetupOpen ? "Done" : "Setup")
                .accessibilityHint(isSetupOpen ? "Returns to the cockpit" : "Opens the settings")
            CockpitIconButton(systemImage: "arrow.clockwise",
                              label: isRefreshing ? "Refreshing limits" : "Refresh limits", action: onRefresh)
                .disabled(isRefreshing)
            CockpitIconButton(systemImage: "power", label: "Quit Burn Bar", isQuiet: true, action: onQuit)
                .keyboardShortcut("q")
        }
        .padding(.vertical, 2)
    }
}

/// Muted mono footer: the how-to-read hint and the last update, then the credits.
struct CockpitFooter: View {
    let updatedAt: Date?
    var hint: String?

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let hint {
                    Text(hint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if let updatedAt {
                    Text("updated \(updatedAt.formatted(.dateTime.hour().minute()))")
                        .fixedSize()
                }
            }
            Text("Burn Bar for macOS · a Mac port of Burn Bar by nixfred")
                .foregroundStyle(palette.tertiary)
        }
        .font(.system(size: 10, design: .monospaced))
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
