//
//  Fixtures.swift
//  burnbarTests
//

import Foundation
@testable import burnbar

/// Grid-aligned reference instant (multiple of 30 min) shifted 10 minutes into its bucket.
let gridStart = Date(timeIntervalSince1970: 1_800_000_000)
let now = gridStart.addingTimeInterval(600)

let hour: TimeInterval = 3600
let minute: TimeInterval = 60
let fiveHours: TimeInterval = 5 * hour
let week: TimeInterval = 7 * 24 * hour

func event(
    _ provider: Provider = .claude,
    at offset: TimeInterval,
    model: String = "opus",
    input: Int = 0,
    cacheWrite: Int = 0,
    output: Int = 0,
    cacheRead: Int = 0,
    session: String? = nil
) -> UsageEvent {
    UsageEvent(
        provider: provider,
        timestamp: now.addingTimeInterval(offset),
        model: model,
        split: TokenSplit(input: input, cacheWrite: cacheWrite, output: output, cacheRead: cacheRead),
        sessionID: session
    )
}

/// A limit row whose window is `elapsed` (0..1) through, with `percent` used.
func row(_ label: String = "Weekly (7-day)", percent: Double, elapsed: Double, window: TimeInterval = week) -> LimitRow {
    LimitRow(
        label: label,
        percent: percent,
        resetsAt: now.addingTimeInterval(window * (1 - elapsed)),
        windowDuration: window
    )
}

func pace(percent: Double, elapsed: Double, window: TimeInterval = week, samples: [LimitSample] = []) -> Pace {
    PaceCalculator.pace(for: row(percent: percent, elapsed: elapsed, window: window), samples: samples, now: now)!
}

func sample(at offset: TimeInterval, _ percent: Double) -> LimitSample {
    LimitSample(t: now.addingTimeInterval(offset), percent: percent)
}
