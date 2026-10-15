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
}
