//
//  CockpitViewTests.swift
//  burnbarTests
//
//  Render smoke tests: the cockpit lays out at its fixed width from synthetic state, offline.
//

import AppKit
import SwiftUI
import Testing
@testable import burnbar

@MainActor
struct CockpitViewTests {
    private func render(_ view: some View) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.nsImage
    }

    private func cockpit(_ cards: [ProviderCard], header: CockpitHeader = CockpitPreview.header,
                         advice: AdviceBanner? = nil, headline: HeadlineMode = .budget) -> some View {
        CockpitView(header: header, advice: advice, cards: cards, headline: headline, glowWhen: .over,
                    isRefreshing: false, onRefresh: {}, onDismissAdvice: {}, onToggleHeadline: {},
                    onOpenSetup: {}, onQuit: {})
            .environment(\.colorScheme, .dark)
    }

    /// One fixed-width column per card, side by side.
    @Test func rendersTheFixtureCockpitOneColumnPerCard() throws {
        let advice = AdviceBanner(advice: .useNext(.codex), cards: CockpitPreview.cards)
        let image = try #require(render(cockpit(CockpitPreview.cards, advice: advice)))
        #expect(CockpitPreview.cards.count == 2)
        #expect(image.size.width == CockpitView.width(columns: 2))
        #expect(CockpitView.width(columns: 2) == 2 * CockpitView.columnWidth + CockpitView.spacing + 2 * CockpitView.padding)
        #expect(image.size.height > 300)
    }

    /// Each fixture card lays out on its own with its rows, burndown chart and token mix: far
    /// taller than a title and a status line, in both headline modes.
    @Test(arguments: CockpitPreview.cards, [HeadlineMode.budget, .tokens])
    func rendersEachFixtureCardWithItsContent(card: ProviderCard, mode: HeadlineMode) throws {
        #expect(card.burndown != nil)
        let view = ProviderCardView(card: card, headline: card.headline(mode, windowLabel: "6 h"),
                                    glow: CardGlow.glow(for: card, when: .spent), windowLabel: "6 h", window: 6 * hour,
                                    onToggleHeadline: {})
            .frame(width: CockpitView.columnWidth)
            .cockpitChrome()
        let image = try #require(render(view))
        #expect(image.size.width == CockpitView.columnWidth)
        #expect(image.size.height > 300)
    }

    /// The scroll view's content is measured, so the cards are laid out inside the cockpit.
    @Test func theCockpitLaysOutItsCards() throws {
        let full = try #require(render(cockpit(CockpitPreview.cards))).size.height
        let empty = try #require(render(cockpit([]))).size.height
        #expect(full > empty + 300)
    }

    @Test func rendersAnEmptyCockpitAtOneColumn() throws {
        let image = try #require(render(cockpit([], header: CockpitHeader(state: .empty))))
        #expect(image.size.width == CockpitView.width(columns: 1))
    }

    @Test(arguments: [(ThemePreference.dark, ColorScheme.dark as ColorScheme?), (.light, .light), (.system, nil)])
    func themeForcesTheColourScheme(theme: ThemePreference, scheme: ColorScheme?) {
        #expect(theme.colorScheme == scheme)
        #expect(CockpitPalette(.light) == .light)
        #expect(CockpitPalette(.dark) == .dark)
    }

    @Test func headlineModeToggles() {
        #expect(HeadlineMode.budget.toggled == .tokens)
        #expect(HeadlineMode.tokens.toggled == .budget)
    }

    /// Writes the fixture cockpit to a PNG for a visual check when `BURNBAR_RENDER_PATH` is set.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BURNBAR_RENDER_PATH"] != nil))
    func writesAFixtureRender() throws {
        let path = try #require(ProcessInfo.processInfo.environment["BURNBAR_RENDER_PATH"])
        let advice = AdviceBanner(advice: .useNext(.codex), cards: CockpitPreview.cards)
        // ImageRenderer leaves scroll views blank, so the columns render on their own here.
        let columns = HStack(alignment: .top, spacing: CockpitView.spacing) {
            ForEach(CockpitPreview.cards) { card in
                ProviderCardView(card: card, headline: card.headline(.budget, windowLabel: "6 h"),
                                 glow: CardGlow.glow(for: card, when: .over), windowLabel: "6 h", window: 6 * hour,
                                 onToggleHeadline: {})
                    .frame(width: CockpitView.columnWidth)
            }
        }
        let page = VStack(spacing: CockpitView.spacing) {
            cockpit([], advice: advice)
            columns.padding(CockpitView.padding).cockpitChrome().environment(\.colorScheme, .dark)
        }
        let renderer = ImageRenderer(content: page)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path))
    }

    @Test func theFixtureCoversARestartedWeeklyOnlyProvider() throws {
        let codex = try #require(CockpitPreview.cards.first { $0.provider == .codex })
        #expect(codex.lines.map(\.label) == ["Weekly (7-day)"])
        #expect(codex.lines.first?.isProjectedReset == true)
        #expect(codex.burndown?.isProjectedReset == true)
    }
}
