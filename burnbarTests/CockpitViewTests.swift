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

    @Test func rendersTheFixtureCockpitAtItsFixedWidth() throws {
        let view = CockpitView(header: CockpitPreview.header, advice: "USE CODEX NEXT", cards: CockpitPreview.cards,
                               isRefreshing: false, onRefresh: {}, onDismissAdvice: {}, onQuit: {})
        let image = try #require(render(view))
        #expect(image.size.width == CockpitView.width)
        #expect(image.size.height > 100)
    }

    /// Each fixture card lays out on its own with its rows, burndown chart and token mix: far
    /// taller than a title and an instruction line.
    @Test(arguments: CockpitPreview.cards)
    func rendersEachFixtureCardWithItsContent(card: ProviderCard) throws {
        #expect(card.burndown != nil)
        let image = try #require(render(ProviderCardView(card: card).frame(width: CockpitView.width - 24)))
        #expect(image.size.width == CockpitView.width - 24)
        #expect(image.size.height > 200)
    }

    /// The scroll view's content is measured, so the cards are laid out inside the cockpit: the
    /// fixture's two cards (each over 200 pt) make it far taller than the empty cockpit.
    @Test func theCockpitLaysOutItsCards() throws {
        func height(_ cards: [ProviderCard]) throws -> CGFloat {
            let view = CockpitView(header: CockpitPreview.header, advice: nil, cards: cards,
                                   isRefreshing: false, onRefresh: {}, onDismissAdvice: {}, onQuit: {})
            return try #require(render(view)).size.height
        }
        #expect(CockpitPreview.cards.count == 2)
        #expect(try height(CockpitPreview.cards) > height([]) + 400)
    }

    @Test func rendersAnEmptyCockpit() throws {
        let view = CockpitView(header: CockpitHeader(state: .empty), advice: nil, cards: UsageViewState.empty.cards(now: now),
                               isRefreshing: true, onRefresh: {}, onDismissAdvice: {}, onQuit: {})
        let image = try #require(render(view))
        #expect(image.size.width == CockpitView.width)
    }

    @Test func theFixtureCoversARestartedWeeklyOnlyProvider() throws {
        let codex = try #require(CockpitPreview.cards.first { $0.provider == .codex })
        #expect(codex.lines.map(\.label) == ["Weekly (7-day)"])
        #expect(codex.lines.first?.isProjectedReset == true)
        #expect(codex.burndown?.isProjectedReset == true)
    }
}
