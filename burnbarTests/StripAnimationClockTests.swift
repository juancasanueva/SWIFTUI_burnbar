//
//  StripAnimationClockTests.swift
//  burnbarTests
//
//  The clock that drives the menu bar strip's motion from outside the label.
//

import Foundation
import Testing
@testable import burnbar

@MainActor
struct StripAnimationClockTests {
    // MARK: Activity decision

    @Test(arguments: [
        // emberEnabled, hasLiveCells, pulsing, reduceMotion, expected
        (true, true, false, false, StripAnimationClock.Activity.ember),
        (true, true, true, false, .ember),
        (false, true, false, false, .still),
        (false, true, true, false, .pulse),
        (true, false, false, false, .still),
        (true, false, true, false, .pulse),
        (true, true, true, true, .still),
        (false, false, false, false, .still),
    ])
    func decidesWhetherTheStripMoves(emberEnabled: Bool, hasLiveCells: Bool, pulsing: Bool, reduceMotion: Bool,
                                     expected: StripAnimationClock.Activity) {
        let activity = StripAnimationClock.activity(
            emberEnabled: emberEnabled, hasLiveCells: hasLiveCells, pulsing: pulsing, reduceMotion: reduceMotion
        )
        #expect(activity == expected)
    }

    @Test func emberTicksAtTheFrameIntervalAndPulseAtItsStep() {
        #expect(StripAnimationClock.Activity.ember.interval == EmberMotion.frameInterval)
        #expect(StripAnimationClock.Activity.pulse.interval == StripAnimationClock.pulseStep)
        #expect(StripAnimationClock.Activity.still.interval == nil)
    }

    @Test func anEmptyStateIsStill() {
        #expect(StripAnimationClock.activity(for: .empty, reduceMotion: false) == .still)
    }

    // MARK: Ticking

    @Test func ticksOnlyWhileActive() {
        let sut = StripAnimationClock()
        #expect(sut.isTicking == false)

        sut.setActivity(.ember)
        #expect(sut.activity == .ember)
        #expect(sut.isTicking)

        sut.setActivity(.still)
        #expect(sut.activity == .still)
        #expect(sut.isTicking == false)
    }

    @Test func aRepeatedActivityKeepsTheSameTicker() {
        let sut = StripAnimationClock()
        sut.setActivity(.pulse)
        let first = sut.tickerID
        sut.setActivity(.pulse)
        #expect(sut.tickerID == first)
        sut.setActivity(.ember)
        #expect(sut.tickerID != first)
        sut.setActivity(.still)
    }
}
