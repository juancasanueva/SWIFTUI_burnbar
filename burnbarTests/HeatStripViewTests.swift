//
//  HeatStripViewTests.swift
//  burnbarTests
//

import Testing
@testable import burnbar

@MainActor
struct HeatStripViewTests {
    @Test(arguments: [
        (-0.5, 2.0),
        (0.0, 2.0),
        (0.5, 9.0),
        (1.0, 18.0),
        (1.7, 18.0),
    ])
    func gaugeFillIsClampedToTheStrip(percent: Double, height: Double) {
        #expect(Double(HeatStripView.gaugeFillHeight(percent: percent)) == height)
    }
}
