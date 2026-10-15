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
