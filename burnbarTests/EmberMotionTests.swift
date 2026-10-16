//
//  EmberMotionTests.swift
//  burnbarTests
//

import Foundation
import Testing
@testable import burnbar

struct EmberMotionTests {
    // MARK: Gating

    @Test(arguments: [
        (false, false, false),
        (false, true, false),
        (true, true, false),
        (true, false, true),
    ])
    func runsOnlyWhenEnabledAndMotionIsAllowed(enabled: Bool, reduceMotion: Bool, expected: Bool) {
        #expect(EmberMotion.isAllowed(enabled: enabled, reduceMotion: reduceMotion) == expected)
    }

    @Test func animatesOnlyWhenSomeLaneHasLiveCells() {
        #expect(EmberMotion.hasLiveCells([[0, 0, 0], [0, 0]]) == false)
        #expect(EmberMotion.hasLiveCells([]) == false)
        #expect(EmberMotion.hasLiveCells([[0, 0], [0, 12]]))
    }

    // MARK: Breathing

    @Test(arguments: [0.0, 0.37, 1.5, 12.25])
    func aStillFrameIsStatic(time: TimeInterval) {
        var frame = EmberFrame.still
        frame.time = time
        #expect(frame.cellIntensity(provider: .claude, index: 3, heat: 5000) == 1)
        #expect(frame.flash(for: .claude) == 0)
    }

    @Test func emptyCellsDoNotBreathe() {
        let frame = EmberFrame(time: 4.2, isActive: true)
        #expect(frame.cellIntensity(provider: .codex, index: 0, heat: 0) == 1)
    }

    @Test func liveCellsBreatheWithinASubtleRange() {
        let intensities = (0..<200).map { step in
            EmberFrame(time: Double(step) * 0.1, isActive: true)
                .cellIntensity(provider: .claude, index: 2, heat: 900)
        }
        #expect(intensities.allSatisfy { $0 >= EmberMotion.minimumIntensity && $0 <= 1 })
        let spread = (intensities.max() ?? 0) - (intensities.min() ?? 0)
        #expect(spread > 0.1)
    }

    @Test func breathingIsDeterministicPerCell() {
        let frame = EmberFrame(time: 7.3, isActive: true)
        let first = frame.cellIntensity(provider: .claude, index: 5, heat: 10)
        let again = frame.cellIntensity(provider: .claude, index: 5, heat: 10)
        #expect(first == again)
    }

    @Test func neighbouringCellsBreatheOutOfPhase() {
        let frame = EmberFrame(time: 3.0, isActive: true)
        let cells = (0..<6).map { frame.cellIntensity(provider: .codex, index: $0, heat: 10) }
        #expect(Set(cells).count > 1)
        #expect(EmberMotion.cellPhase(provider: .claude, index: 0)
                != EmberMotion.cellPhase(provider: .codex, index: 0))
    }

    @Test(arguments: 0..<24)
    func cellPhaseStaysInAUnitRange(index: Int) {
        for provider in Provider.allCases {
            let phase = EmberMotion.cellPhase(provider: provider, index: index)
            #expect(phase >= 0 && phase < 1)
        }
    }

    // MARK: Flash on new burn

    @Test func aLaneFlashesWhenItsLatestBucketGrows() {
        let flashing = EmberMotion.flashingLanes(
            previous: [.claude: 100, .codex: 50],
            current: [.claude: 180, .codex: 50]
        )
        #expect(flashing == [.claude])
    }

    @Test func noFlashForUnchangedShrinkingOrNewLanes() {
        let flashing = EmberMotion.flashingLanes(
            previous: [.claude: 400],
            current: [.claude: 0, .codex: 900]
        )
        #expect(flashing.isEmpty)
    }

    @Test func flashFadesOutOverItsDuration() {
        #expect(EmberMotion.flashIntensity(elapsed: 0) == 1)
        #expect(EmberMotion.flashIntensity(elapsed: -1) == 0)
        #expect(EmberMotion.flashIntensity(elapsed: EmberMotion.flashDuration) == 0)
        #expect(EmberMotion.flashIntensity(elapsed: 60) == 0)
        let early = EmberMotion.flashIntensity(elapsed: EmberMotion.flashDuration * 0.25)
        let late = EmberMotion.flashIntensity(elapsed: EmberMotion.flashDuration * 0.75)
        #expect(early > late && late > 0)
    }

    @Test func frameFlashesFollowTheirStartTimes() {
        let start = Date(timeIntervalSinceReferenceDate: 1000)
        let frame = EmberFrame(
            date: start.addingTimeInterval(EmberMotion.flashDuration / 2),
            isActive: true,
            flashStarts: [.claude: start]
        )
        #expect(frame.flash(for: .claude) > 0 && frame.flash(for: .claude) < 1)
        #expect(frame.flash(for: .codex) == 0)

        let gated = EmberFrame(date: start, isActive: false, flashStarts: [.claude: start])
        #expect(gated.flash(for: .claude) == 0)
    }
}
