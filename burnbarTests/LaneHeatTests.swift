//
//  LaneHeatTests.swift
//  burnbarTests
//

import Testing
@testable import burnbar

struct LaneHeatTests {
    private let lane = LanePalette.claude

    @Test func idleCellsAndAnIdleStripAreCold() {
        #expect(lane.color(heat: 0, max: 100) == lane.cold)
        #expect(lane.color(heat: 0, max: 0) == lane.cold)
        #expect(lane.color(heat: 5, max: 0) == lane.cold)
    }

    @Test func rampsColdToWarmToHot() {
        #expect(lane.color(heat: 50, max: 100) == lane.warm)
        #expect(lane.color(heat: 100, max: 100) == lane.hot)
        #expect(lane.color(heat: 250, max: 100) == lane.hot)
    }

    @Test func interpolatesEachChannel() {
        // A quarter of the max is halfway from cold (#4A2113) to warm (#C4542A).
        #expect(lane.color(heat: 25, max: 100) == RGBHex(0x873B1F))
        // Three quarters is halfway from warm (#C4542A) to hot (#FF8A4B).
        #expect(LanePalette.codex.color(heat: 75, max: 100) == RGBHex(0x1FC095))
    }

    @Test func mixClampsItsFraction() {
        let black = RGBHex(0x000000), white = RGBHex(0xFFFFFF)
        #expect(black.mix(white, -1) == black)
        #expect(black.mix(white, 2) == white)
        #expect(black.mix(white, 0.5) == RGBHex(0x808080))
    }
}
