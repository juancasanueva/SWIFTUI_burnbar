//
//  ModelsTests.swift
//  burnbarTests
//

import Testing
@testable import burnbar

struct ModelsTests {
    @Test func heatExcludesCacheReads() {
        let split = TokenSplit(input: 10, cacheWrite: 20, output: 30, cacheRead: 1_000)
        #expect(split.heat == 60)
    }

    @Test func splitsAddFieldByField() {
        let sum = TokenSplit(input: 1, cacheWrite: 2, output: 3, cacheRead: 4)
            + TokenSplit(input: 10, cacheWrite: 20, output: 30, cacheRead: 40)
        #expect(sum == TokenSplit(input: 11, cacheWrite: 22, output: 33, cacheRead: 44))
    }

    @Test func providersAreClaudeAndCodex() {
        #expect(Provider.allCases == [.claude, .codex])
        #expect(Provider.claude.displayName == "CLAUDE")
        #expect(Provider.codex.displayName == "CODEX")
    }

    @Test func lanePaletteMatchesUpstreamHex() {
        #expect(LanePalette.lane(for: .claude) == Lane(cold: RGBHex(0x4A2113), warm: RGBHex(0xC4542A), hot: RGBHex(0xFF8A4B)))
        #expect(LanePalette.lane(for: .codex) == Lane(cold: RGBHex(0x0C3E33), warm: RGBHex(0x12977A), hot: RGBHex(0x2BE8B0)))
        #expect(LanePalette.amber == RGBHex(0xFFC46B))
        #expect(LanePalette.whiteHot == RGBHex(0xFFF6EC))
    }

    @Test func rgbHexExposesUnitComponents() {
        let color = RGBHex(0xFF8000)
        #expect(color.red == 1)
        #expect(abs(color.green - 128.0 / 255.0) < 1e-9)
        #expect(color.blue == 0)
    }
}
