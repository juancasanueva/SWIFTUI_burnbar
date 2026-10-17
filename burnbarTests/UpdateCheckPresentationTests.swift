//
//  UpdateCheckPresentationTests.swift
//  burnbarTests
//
//  The "last checked" wording. Deterministic because `now` is injected.
//

import Foundation
import Testing
@testable import burnbar

@Suite("Update check presentation")
struct UpdateCheckPresentationTests {
    private static let now = Date(timeIntervalSince1970: 1_787_000_000)

    /// No digits at all: a fabricated date, a placeholder and the Unix epoch all read as
    /// plausible sentences, and "there is no number in it" rules out all three.
    @Test func aNeverCheckedAppSaysSoWithNoDateInTheText() {
        let presentation = UpdateCheckPresentation(lastCheck: nil, now: Self.now)

        #expect(presentation.label == "Never checked")
        #expect(presentation.label.rangeOfCharacter(from: .decimalDigits) == nil)
    }

    /// The label is derived from the date: three offsets, three distinct labels.
    @Test func aCheckedAppReportsItsCheckAndTheLabelFollowsTheDate() {
        let offsets: [TimeInterval] = [-3600, -3 * 86_400, -21 * 86_400]

        let labels = offsets.map { offset in
            UpdateCheckPresentation(lastCheck: Self.now.addingTimeInterval(offset), now: Self.now).label
        }

        for label in labels {
            #expect(label.hasPrefix("Last checked "))
            #expect(label.count > "Last checked ".count)
        }
        #expect(Set(labels).count == 3)
    }

    @Test func theLabelIsAPureFunctionOfTheTwoDates() {
        let checked = Self.now.addingTimeInterval(-7200)

        let first = UpdateCheckPresentation(lastCheck: checked, now: Self.now)
        let second = UpdateCheckPresentation(lastCheck: checked, now: Self.now)

        #expect(first == second)
        #expect(first.label == second.label)
    }

    /// An app that has just checked must stop saying it never has.
    @Test func theLabelChangesWhenTheRecordedDateArrives() {
        let before = UpdateCheckPresentation(lastCheck: nil, now: Self.now)
        let after = UpdateCheckPresentation(lastCheck: Self.now.addingTimeInterval(-60), now: Self.now)

        #expect(before.label == "Never checked")
        #expect(after.label != before.label)
        #expect(after.label.hasPrefix("Last checked "))
    }
}
