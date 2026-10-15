//
//  CodexRolloutCollectorTests.swift
//  burnbarTests
//

import Foundation
import Testing
@testable import burnbar

/// Runs against real temporary files, so `clock` follows wall time to match file modification dates.
final class CodexRolloutCollectorTests {
    private let root: URL
    private let clock = Date()

    init() throws {
        root = try makeTemporaryDirectory()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ name: String) -> URL { root.appending(path: "2026/10/16/\(name)") }

    private func collector() -> CodexRolloutCollector { CodexRolloutCollector(root: root) }

    private func window(_ percent: Double, minutes: Int = 300) -> CodexWindowFixture {
        CodexWindowFixture(usedPercent: percent, windowMinutes: minutes, resetsAt: clock.addingTimeInterval(2 * hour))
    }

    @Test func readsOnlyRolloutFiles() async throws {
        try writeLines([codexTokenLine(at: clock.addingTimeInterval(-60), total: codexUsage(input: 10, output: 1))], to: file("rollout-a.jsonl"))
        try writeLines([codexTokenLine(at: clock.addingTimeInterval(-60), total: codexUsage(input: 10, output: 1))], to: file("history.jsonl"))

        let events = await collector().events(now: clock)
        #expect(events.count == 1)
        #expect(events.first?.sessionID == "rollout-a")
    }

    @Test func picksUpDeltasAcrossAppends() async throws {
        let url = file("rollout-a.jsonl")
        try writeLines([
            codexTurnContextLine(at: clock.addingTimeInterval(-300), model: "gpt-5-codex"),
            codexTokenLine(at: clock.addingTimeInterval(-240), total: codexUsage(input: 100, cached: 40, output: 10)),
        ], to: url)
        let sut = collector()
        #expect(await sut.events(now: clock).map(\.split.input) == [60])

        try appendText(codexTokenLine(at: clock.addingTimeInterval(-120), total: codexUsage(input: 100, cached: 40, output: 10)) + "\n", to: url)
        try appendText(codexTokenLine(at: clock.addingTimeInterval(-60), total: codexUsage(input: 250, cached: 90, output: 30)) + "\n", to: url)
        let events = await sut.events(now: clock)
        #expect(events.map(\.split.input) == [60, 100])
        #expect(events.map(\.split.output) == [10, 20])
        #expect(events.allSatisfy { $0.model == "gpt-5-codex" })
    }

    @Test func rewrittenRolloutIsDerivedAgain() async throws {
        let url = file("rollout-a.jsonl")
        try writeLines([codexTokenLine(at: clock.addingTimeInterval(-240), total: codexUsage(input: 100, output: 10))], to: url)
        let sut = collector()
        #expect(await sut.events(now: clock).count == 1)

        try writeLines([
            codexTokenLine(at: clock.addingTimeInterval(-120), total: codexUsage(input: 7, output: 1)),
            codexTokenLine(at: clock.addingTimeInterval(-60), total: codexUsage(input: 9, output: 2)),
        ], to: url)
        #expect(await sut.events(now: clock).map(\.split.input) == [7, 2])
    }

    @Test func deletedRolloutDropsItsBurn() async throws {
        let url = file("rollout-a.jsonl")
        try writeLines([codexTokenLine(at: clock.addingTimeInterval(-60), total: codexUsage(input: 10, output: 1))], to: url)
        let sut = collector()
        #expect(await sut.events(now: clock).count == 1)

        try FileManager.default.removeItem(at: url)
        #expect(await sut.events(now: clock).isEmpty)
    }

    @Test func limitsComeFromTheNewestRecordAcrossFiles() async throws {
        try writeLines([
            codexTokenLine(at: clock.addingTimeInterval(-60), primary: window(70), secondary: window(20, minutes: 10080)),
        ], to: file("rollout-a.jsonl"))
        try writeLines([
            codexTokenLine(at: clock.addingTimeInterval(-300), primary: window(10)),
            codexTokenLine(at: clock.addingTimeInterval(-200), total: codexUsage(input: 1, output: 1)),
        ], to: file("rollout-b.jsonl"))

        let snapshot = try #require(await collector().limits(now: clock))
        #expect(snapshot.rows.map(\.percent) == [0.7, 0.2])
        #expect(snapshot.rows.map(\.label) == ["Session (5-hour)", "Weekly (7-day)"])
        #expect(abs(snapshot.measuredAt.timeIntervalSince(clock.addingTimeInterval(-60))) < 0.001)
    }

    @Test func limitsFollowNewerAppends() async throws {
        let url = file("rollout-a.jsonl")
        try writeLines([codexTokenLine(at: clock.addingTimeInterval(-120), primary: window(10))], to: url)
        let sut = collector()
        #expect(await sut.limits(now: clock)?.rows.first?.percent == 0.1)

        try appendText(codexTokenLine(at: clock.addingTimeInterval(-30), primary: window(55)) + "\n", to: url)
        #expect(await sut.limits(now: clock)?.rows.first?.percent == 0.55)
    }

    @Test func limitsAreFoundInRolloutsOlderThanTheBurnWindow() async throws {
        let older = file("rollout-older.jsonl")
        let newest = file("rollout-newest.jsonl")
        try writeLines([codexTokenLine(at: clock.addingTimeInterval(-20 * hour), primary: window(5))], to: older)
        try writeLines([
            codexTokenLine(at: clock.addingTimeInterval(-10 * hour), total: codexUsage(input: 10, output: 1), primary: window(64)),
        ], to: newest)
        try FileManager.default.setAttributes([.modificationDate: clock.addingTimeInterval(-20 * hour)], ofItemAtPath: older.path)
        try FileManager.default.setAttributes([.modificationDate: clock.addingTimeInterval(-10 * hour)], ofItemAtPath: newest.path)

        let sut = collector()
        #expect(await sut.events(now: clock).isEmpty)
        #expect(await sut.limits(now: clock)?.rows.first?.percent == 0.64)
    }

    @Test func noRateLimitsYieldsNoSnapshot() async throws {
        try writeLines([codexTokenLine(at: clock.addingTimeInterval(-60), total: codexUsage(input: 10, output: 1))], to: file("rollout-a.jsonl"))
        #expect(await collector().limits(now: clock) == nil)
        #expect(await CodexRolloutCollector(root: root.appending(path: "missing")).limits(now: clock) == nil)
    }
}
