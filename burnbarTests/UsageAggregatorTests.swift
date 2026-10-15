//
//  UsageAggregatorTests.swift
//  burnbarTests
//

import Foundation
import Testing
@testable import burnbar

struct UsageAggregatorTests {
    @Test func bucketsAreTwelveHalfHoursAlignedToGrid() {
        let summary = UsageAggregator.summarize([], now: now)
        #expect(summary.bucketStarts.count == 12)
        #expect(summary.bucketStarts.last == gridStart)
        #expect(summary.bucketStarts.first == gridStart.addingTimeInterval(-11 * 1800))
    }

    @Test func eventsLandInTheirGridBucket() {
        let events = [
            event(at: -minute, input: 5),                     // current bucket
            event(at: -601, input: 7),                        // 1 s before the current bucket
            event(at: -600 - 11 * 1800, input: 11),           // first bucket start
        ]
        let lane = UsageAggregator.summarize(events, now: now).lane(.claude)
        #expect(lane.buckets[11] == 5)
        #expect(lane.buckets[10] == 7)
        #expect(lane.buckets[0] == 11)
        #expect(lane.buckets.reduce(0, +) == 23)
    }

    @Test func headlineTotalsUseExactTrailingWindow() {
        let events = [
            event(at: -21_000, input: 100),   // inside 360 min, before first grid bucket
            event(at: -21_601, input: 1_000), // just outside 360 min
            event(at: 60, input: 9_999),      // future
            event(at: -minute, output: 1),
        ]
        let lane = UsageAggregator.summarize(events, now: now).lane(.claude)
        #expect(lane.heat == 101)
        #expect(lane.buckets.reduce(0, +) == 1)
        #expect(lane.turns == 2)
    }

    @Test func lanesAreSeparatedPerProvider() {
        let events = [event(.claude, at: -minute, input: 3), event(.codex, at: -minute, output: 4)]
        let summary = UsageAggregator.summarize(events, now: now)
        #expect(summary.lane(.claude).heat == 3)
        #expect(summary.lane(.codex).heat == 4)
        #expect(summary.totalHeat == 7)
    }

    @Test func peakBucketIsTheHottest() {
        let events = [event(at: -minute, input: 5), event(at: -2 * hour, input: 50), event(.codex, at: -minute, input: 80)]
        let summary = UsageAggregator.summarize(events, now: now)
        #expect(summary.lane(.claude).peakBucketHeat == 50)
        #expect(summary.lane(.claude).peakBucketIndex == 7)
        #expect(summary.peakBucketHeat == 80)
        #expect(UsageAggregator.summarize([], now: now).lane(.claude).peakBucketIndex == nil)
    }

    @Test func trailingRatesAreTokensPerMinute() {
        let events = [event(at: -2 * minute, input: 50), event(at: -30 * minute, input: 550), event(at: -2 * hour, input: 10_000)]
        let lane = UsageAggregator.summarize(events, now: now).lane(.claude)
        #expect(lane.rate5m == 10)
        #expect(lane.rate60m == 10)
    }

    @Test func splitAndModelsAreSummedHottestFirst() {
        let events = [
            event(at: -minute, model: "sonnet", input: 1, cacheRead: 100),
            event(at: -minute, model: "opus", output: 10, cacheRead: 5),
            event(at: -2 * minute, model: "sonnet", cacheWrite: 2),
        ]
        let lane = UsageAggregator.summarize(events, now: now).lane(.claude)
        #expect(lane.split == TokenSplit(input: 1, cacheWrite: 2, output: 10, cacheRead: 105))
        #expect(lane.byModel.map(\.model) == ["opus", "sonnet"])
        #expect(lane.byModel.last?.split == TokenSplit(input: 1, cacheWrite: 2, output: 0, cacheRead: 100))
    }

    @Test func sessionsCountDistinctIdsPerProvider() {
        let events = [
            event(at: -minute, input: 1, session: "a"),
            event(at: -minute, input: 1, session: "a"),
            event(at: -minute, input: 1, session: "b"),
            event(at: -minute, input: 1),
            event(.codex, at: -minute, input: 1, session: "a"),
        ]
        let summary = UsageAggregator.summarize(events, now: now)
        #expect(summary.lane(.claude).sessions == 2)
        #expect(summary.lane(.claude).turns == 4)
        #expect(summary.sessions == 3)
        #expect(summary.turns == 5)
    }
}
