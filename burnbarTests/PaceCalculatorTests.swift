//
//  PaceCalculatorTests.swift
//  burnbarTests
//

import Foundation
import Testing
@testable import burnbar

struct PaceCalculatorTests {
    private func close(_ a: Double?, _ b: Double, _ tolerance: Double = 1e-9) -> Bool {
        guard let a else { return false }
        return abs(a - b) < tolerance
    }

    private func close(_ a: Date?, _ b: Date) -> Bool {
        guard let a else { return false }
        return abs(a.timeIntervalSince(b)) < 1e-3
    }

    @Test func fiveHourWindowCoreFormulas() {
        // 2 h of 5 h elapsed, 50% used, 3 h left.
        let samples = [sample(at: -30 * minute, 0.4), sample(at: -15 * minute, 0.45), sample(at: 0, 0.5)]
        let p = pace(percent: 0.5, elapsed: 0.4, window: fiveHours, samples: samples)
        #expect(close(p.elapsed, 0.4))
        #expect(close(p.ratio, 1.25))
        #expect(close(p.hoursLeft, 3))
        #expect(close(p.allowancePerHour, 0.5 / 3))
        #expect(close(p.ratePerHour, 0.2))
        #expect(close(p.projected, 1.1))
        #expect(close(p.dryAt, now.addingTimeInterval(2.5 * hour)))
        #expect(close(p.backOnPaceAt, now.addingTimeInterval(0.5 * hour)))
        #expect(close(p.banked, -0.1))
        #expect(p.todayCeiling == nil)
    }

    @Test func ratioNeedsOnePercentElapsed() {
        #expect(pace(percent: 0.02, elapsed: 0.005).ratio == nil)
        #expect(pace(percent: 0.02, elapsed: 0.011).ratio != nil)
    }

    // Deliberate deviation from upstream: a passed reset means the window restarted, so the row
    // reads 0% used with a reset projected forward by whole windows.

    @Test func passedResetRestartsAtZeroWithAProjectedReset() throws {
        let passed = LimitRow(label: "Weekly (7-day)", percent: 0.12, resetsAt: now.addingTimeInterval(-2 * 24 * hour), windowDuration: week)
        let p = try #require(PaceCalculator.pace(for: passed, samples: [], now: now))
        #expect(p.isProjectedReset)
        #expect(p.percent == 0)
        #expect(p.row.percent == 0)
        #expect(p.row.label == "Weekly (7-day)")
        #expect(p.row.resetsAt == now.addingTimeInterval(5 * 24 * hour))
        #expect(close(p.elapsed, 2.0 / 7))
        #expect(p.ratio == 0)
        #expect(p.verdict == .onTrack)
        #expect(close(p.allowancePerHour, 1 / (5 * 24)))
    }

    @Test func projectedResetRollsForwardByWholeWindows() throws {
        let passed = LimitRow(label: "x", percent: 0.5, resetsAt: now.addingTimeInterval(-12 * hour), windowDuration: fiveHours)
        let p = try #require(PaceCalculator.pace(for: passed, samples: [], now: now))
        #expect(p.row.resetsAt == now.addingTimeInterval(3 * hour))
        #expect(close(p.elapsed, 0.4))
    }

    @Test func aResetExactlyNowStartsAFreshWindow() throws {
        let edge = LimitRow(label: "x", percent: 0.5, resetsAt: now, windowDuration: fiveHours)
        let p = try #require(PaceCalculator.pace(for: edge, samples: [], now: now))
        #expect(p.isProjectedReset)
        #expect(p.row.resetsAt == now.addingTimeInterval(fiveHours))
        #expect(p.elapsed == 0)
        #expect(p.ratio == nil)
    }

    @Test func aResetStillAheadIsUnchanged() throws {
        let ahead = row(percent: 0.3, elapsed: 0.5)
        let p = try #require(PaceCalculator.pace(for: ahead, samples: [], now: now))
        #expect(p.isProjectedReset == false)
        #expect(p.row == ahead)
        #expect(p.percent == 0.3)
    }

    @Test func aPassedResetWithoutAWindowIsUnknown() {
        let passed = LimitRow(label: "x", percent: 0.5, resetsAt: now.addingTimeInterval(-60), windowDuration: 0)
        #expect(PaceCalculator.pace(for: passed, samples: [], now: now) == nil)
    }

    @Test func aProjectedWindowIgnoresSamplesFromThePreviousWindow() throws {
        // Reset 20 min ago: samples before it belong to the old window and must not drive the fit.
        let passed = LimitRow(label: "x", percent: 0.6, resetsAt: now.addingTimeInterval(-20 * minute), windowDuration: fiveHours)
        let samples = [sample(at: -50 * minute, 0.4), sample(at: -25 * minute, 0.6)]
        let p = try #require(PaceCalculator.pace(for: passed, samples: samples, now: now))
        #expect(p.ratePerHour == nil)
        #expect(p.dryAt == nil)
    }

    @Test func rateUsesTenPercentOfShortWindows() {
        // 5 h window → 30 min lookback; the old sample would flatten the slope.
        let samples = [sample(at: -2 * hour, 0.0), sample(at: -30 * minute, 0.4), sample(at: 0, 0.5)]
        let p = pace(percent: 0.5, elapsed: 0.4, window: fiveHours, samples: samples)
        #expect(close(p.ratePerHour, 0.2))
    }

    @Test func rateUsesTwoHoursOfLongWindows() {
        let samples = [sample(at: -3 * hour, 0.0), sample(at: -2 * hour, 0.10), sample(at: 0, 0.20)]
        let p = pace(percent: 0.2, elapsed: 0.5, samples: samples)
        #expect(close(p.ratePerHour, 0.05))
    }

    @Test func rateNeedsTenMinutesOfSpan() {
        let samples = [sample(at: -9 * minute, 0.4), sample(at: 0, 0.5)]
        let p = pace(percent: 0.5, elapsed: 0.4, window: fiveHours, samples: samples)
        #expect(p.ratePerHour == nil)
        #expect(p.projected == nil)
        #expect(p.dryAt == nil)
    }

    @Test func rateIgnoresSamplesFromPreviousReset() {
        // Window started 1 h ago (20% of 5 h); earlier samples belong to the last window.
        let samples = [sample(at: -70 * minute, 0.95), sample(at: -20 * minute, 0.1), sample(at: 0, 0.2)]
        let p = pace(percent: 0.2, elapsed: 0.2, window: fiveHours, samples: samples)
        #expect(close(p.ratePerHour, 0.3))
    }

    @Test func giftDropRebasesSamples() {
        let samples = [
            sample(at: -90 * minute, 0.30), sample(at: -60 * minute, 0.35),
            sample(at: -45 * minute, 0.10), sample(at: -30 * minute, 0.12), sample(at: -15 * minute, 0.14),
        ]
        let p = pace(percent: 0.14, elapsed: 0.5, samples: samples)
        #expect(close(p.ratePerHour, 0.08))
    }

    @Test func smallDropIsNotAGift() {
        let samples = [sample(at: -60 * minute, 0.30), sample(at: -30 * minute, 0.28), sample(at: 0, 0.30)]
        let p = pace(percent: 0.30, elapsed: 0.5, samples: samples)
        #expect(close(p.ratePerHour, 0))
        #expect(p.dryAt == nil)
    }

    @Test func dailyCeilingOnlyForLongWindows() {
        // 7 d window with 48 h left.
        let weekly = pace(percent: 0.6, elapsed: 1 - 48.0 / 168.0)
        #expect(close(weekly.todayCeiling, 0.4 * 0.5))
        // 36 h window with 12 h left: min(1, 24/12) = 1.
        let shortest = pace(percent: 0.5, elapsed: 2.0 / 3.0, window: 36 * hour)
        #expect(close(shortest.todayCeiling, 0.5))
        #expect(pace(percent: 0.5, elapsed: 0.5, window: 35 * hour).todayCeiling == nil)
    }

    @Test func percentIsClampedLikeDerivedValues() {
        let over = pace(percent: 1.2, elapsed: 0.5)
        #expect(over.percent == 1)
        #expect(close(over.banked, -0.5))
        #expect(close(over.ratio, 2))
        #expect(pace(percent: -0.1, elapsed: 0.5).percent == 0)
    }

    @Test func backOnPaceOnlyWhenAhead() {
        #expect(pace(percent: 0.2, elapsed: 0.5).backOnPaceAt == nil)
    }

    @Test func staleAfterMaxOfFifteenMinutesOrThreeRefreshes() {
        #expect(PaceCalculator.isStale(fetchedAt: now.addingTimeInterval(-901), refreshInterval: 300, now: now))
        #expect(!PaceCalculator.isStale(fetchedAt: now.addingTimeInterval(-899), refreshInterval: 300, now: now))
        #expect(!PaceCalculator.isStale(fetchedAt: now.addingTimeInterval(-1_100), refreshInterval: 400, now: now))
    }
}
