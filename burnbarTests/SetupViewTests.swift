//
//  SetupViewTests.swift
//  burnbarTests
//
//  Render smoke tests for the setup screen, offline, from fixture values.
//

import AppKit
import SwiftUI
import Testing
@testable import burnbar

@MainActor
struct SetupViewTests {
    @Test func rendersThreeColumnsAtItsFixedWidth() throws {
        let renderer = ImageRenderer(content: SetupView.preview.environment(\.colorScheme, .dark))
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        #expect(image.size.width == SetupView.width)
        #expect(SetupView.width == 3 * SetupView.columnWidth + 2 * SetupView.columnSpacing + 2 * CockpitView.padding)
        #expect(image.size.height > 400)
    }

    /// Writes the fixture setup screen to a PNG for a visual check when `BURNBAR_SETUP_RENDER_PATH` is set.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BURNBAR_SETUP_RENDER_PATH"] != nil))
    func writesAFixtureRender() throws {
        let path = try #require(ProcessInfo.processInfo.environment["BURNBAR_SETUP_RENDER_PATH"])
        let renderer = ImageRenderer(content: SetupView.preview.environment(\.colorScheme, .dark))
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        let tiff = try #require(image.tiffRepresentation)
        let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: path))
    }
}
