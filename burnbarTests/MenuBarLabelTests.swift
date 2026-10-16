//
//  MenuBarLabelTests.swift
//  burnbarTests
//

import AppKit
import Testing
@testable import burnbar

@MainActor
struct MenuBarLabelTests {
    @Test func rendersAColouredStripEighteenPointsTall() throws {
        let image = try #require(MenuBarLabel.image(for: .empty, scale: 2))
        #expect(image.isTemplate == false)
        #expect(image.size.height == HeatStripView.height)
        #expect(image.size.width > 40)
    }

    @Test func rendersAnEmberFrameAtTheSameSize() throws {
        let frame = EmberFrame(time: 2.5, isActive: true, flashes: [.claude: 0.8])
        let still = try #require(MenuBarLabel.image(for: .empty, scale: 2))
        let ember = try #require(MenuBarLabel.image(for: .empty, ember: frame, scale: 2))
        #expect(ember.size == still.size)
    }
}
