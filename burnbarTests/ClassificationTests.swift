//
//  ClassificationTests.swift
//  burnbarTests
//

import Testing
@testable import burnbar

struct ClassificationTests {
    @Test(arguments: [
        (1.51, Verdict.wayOver), (1.5, .over), (1.06, .over), (1.05, .atPace),
        (0.91, .atPace), (0.9, .onTrack), (0.0, .onTrack),
    ])
    func verdictThresholds(ratio: Double, expected: Verdict) {
        #expect(Verdict(ratio: ratio) == expected)
    }

    @Test func unknownRatioIsOnTrack() {
        #expect(Verdict(ratio: nil) == .onTrack)
        #expect(Verdict.wayOver.title == "WAY OVER")
        #expect(Verdict.atPace.title == "AT PACE")
    }

    @Test(arguments: [
        (1.0, 0.5, Stage.calm), (1.06, 0.5, .over), (1.51, 0.5, .wayOver),
        (2.51, 0.5, .burning), (0.5, 0.995, .full), (nil, 0.2, .calm),
    ] as [(Double?, Double, Stage)])
    func stageThresholds(ratio: Double?, percent: Double, expected: Stage) {
        #expect(Stage(ratio: ratio, percent: percent) == expected)
    }

    @Test func stagesAreOrdered() {
        #expect(Stage.calm < Stage.over && Stage.burning < Stage.full)
        #expect(Stage.full.rawValue == 4)
    }

    @Test(arguments: [(0.95, GaugeLevel.red), (0.9, .red), (0.89, .yellow), (0.75, .yellow), (0.74, .green)])
    func gaugeThresholds(percent: Double, expected: GaugeLevel) {
        #expect(GaugeLevel(percent: percent) == expected)
    }

    @Test func gaugePulsesFromNinetyPercent() {
        #expect(GaugeLevel.pulses(percent: 0.9))
        #expect(!GaugeLevel.pulses(percent: 0.89))
    }

    @Test func overNeedsOnePercentBehindAndFivePercentRatio() {
        #expect(pace(percent: 0.5, elapsed: 0.4).isOver)
        #expect(!pace(percent: 0.52, elapsed: 0.5).isOver)     // ratio 1.04, not > 1.05
        #expect(!pace(percent: 0.0505, elapsed: 0.045).isOver) // behind < 1%
    }
}
