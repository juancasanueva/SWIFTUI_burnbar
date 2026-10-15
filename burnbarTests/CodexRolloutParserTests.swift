//
//  CodexRolloutParserTests.swift
//  burnbarTests
//

import Foundation
import Testing
@testable import burnbar

struct CodexRolloutParserTests {
    private func parse(_ line: String) -> CodexRolloutRecord? {
        CodexRolloutParser.record(from: Data(line.utf8))
    }

    private func tokenCount(_ line: String) throws -> CodexTokenCount {
        guard case .tokenCount(let count) = try #require(parse(line)) else {
            Issue.record("expected a token_count record")
            throw CancellationError()
        }
        return count
    }

    private let fiveHour = CodexWindowFixture(usedPercent: 42, windowMinutes: 300, resetsAt: now.addingTimeInterval(2 * hour))
    private let weekly = CodexWindowFixture(usedPercent: 31, windowMinutes: 10080, resetsAt: now.addingTimeInterval(3 * 24 * hour))

    @Test func parsesTokenCountLine() throws {
        let line = codexTokenLine(
            at: now,
            total: codexUsage(input: 1000, cached: 600, cacheWrite: 50, output: 200),
            last: codexUsage(input: 100, cached: 60, cacheWrite: 5, output: 20),
            primary: fiveHour,
            secondary: weekly
        )
        let count = try tokenCount(line)
        #expect(abs(count.timestamp.timeIntervalSince(now)) < 0.001)
        #expect(count.total == codexUsage(input: 1000, cached: 600, cacheWrite: 50, output: 200))
        #expect(count.last == codexUsage(input: 100, cached: 60, cacheWrite: 5, output: 20))
        #expect(count.primary == CodexRateWindow(usedPercent: 42, windowMinutes: 300, resetsAt: Date(timeIntervalSince1970: fiveHour.resetsAt.timeIntervalSince1970.rounded(.down))))
        #expect(count.secondary?.windowMinutes == 10080)
    }

    @Test func nullInfoKeepsRateLimits() throws {
        let count = try tokenCount(codexTokenLine(at: now, primary: fiveHour))
        #expect(count.total == nil)
        #expect(count.last == nil)
        #expect(count.primary?.usedPercent == 42)
        #expect(count.secondary == nil)
    }

    @Test func missingCacheWriteCountsAsZero() throws {
        let line = codexTokenLine(at: now, total: codexUsage(input: 10, cached: 4, cacheWrite: 99, output: 2), includeCacheWrite: false)
        #expect(try tokenCount(line).total == codexUsage(input: 10, cached: 4, cacheWrite: 0, output: 2))
    }

    @Test func parsesTurnContextModel() {
        #expect(parse(codexTurnContextLine(at: now, model: "gpt-5.2-codex")) == .turnContext(model: "gpt-5.2-codex"))
    }

    @Test(arguments: [
        "",
        "not json",
        #"{"timestamp":"2026-10-15T22:21:41.775Z","type":"event_msg","payload":{"type":"agent_message","message":"token_count"}}"#,
        #"{"timestamp":"yesterday","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":null}}"#,
        #"{"timestamp":"2026-10-15T22:21:41.775Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1"#,
        #"{"timestamp":"2026-10-15T22:21:41.775Z","type":"turn_context","payload":{"cwd":"/tmp"}}"#,
    ])
    func rejectsUnusableLines(line: String) {
        #expect(parse(line) == nil)
    }

    @Test func snapshotMapsWindowsToLimitRows() throws {
        let count = try tokenCount(codexTokenLine(at: now, primary: fiveHour, secondary: weekly))
        let snapshot = try #require(CodexRolloutParser.snapshot(from: count))
        #expect(snapshot.provider == .codex)
        #expect(snapshot.measuredAt == count.timestamp)
        #expect(snapshot.rows.map(\.label) == ["Session (5-hour)", "Weekly (7-day)"])
        #expect(snapshot.rows.map(\.percent) == [0.42, 0.31])
        #expect(snapshot.rows.map(\.windowDuration) == [5 * hour, week])
        #expect(snapshot.rows.first?.resetsAt == count.primary?.resetsAt)
    }

    @Test func snapshotIsNilWithoutWindows() throws {
        let count = try tokenCount(codexTokenLine(at: now, total: codexUsage(input: 1, output: 1)))
        #expect(CodexRolloutParser.snapshot(from: count) == nil)
    }

    @Test(arguments: [
        (300, "Session (5-hour)"),
        (90, "Session (90-minute)"),
        (10080, "Weekly (7-day)"),
        (1440, "Daily (1-day)"),
        (43200, "Window (30-day)"),
        (2880, "Window (2-day)"),
    ])
    func labelsFollowWindowLength(minutes: Int, label: String) {
        #expect(LimitRow.label(windowMinutes: minutes) == label)
    }
}

struct CodexBurnTrackerTests {
    private func count(at offset: TimeInterval, total: CodexTokenUsage?, last: CodexTokenUsage? = nil) throws -> CodexRolloutRecord {
        try #require(CodexRolloutParser.record(from: Data(codexTokenLine(at: now.addingTimeInterval(offset), total: total, last: last).utf8)))
    }

    @Test func firstTotalIsTheFirstDeltaWithFreshInputSplit() throws {
        var tracker = CodexBurnTracker()
        let emitted = tracker.ingest(try count(at: 0, total: codexUsage(input: 1000, cached: 600, cacheWrite: 50, output: 200)), sessionID: "s")
        let event = try #require(emitted)
        #expect(event.provider == .codex)
        #expect(event.model == "codex")
        #expect(event.sessionID == "s")
        #expect(event.split == TokenSplit(input: 400, cacheWrite: 50, output: 200, cacheRead: 600))
    }

    @Test func burnIsTheDeltaOfSuccessiveTotals() throws {
        var tracker = CodexBurnTracker()
        _ = tracker.ingest(try count(at: 0, total: codexUsage(input: 1000, cached: 600, output: 200)), sessionID: "s")
        let emitted = tracker.ingest(try count(at: 60, total: codexUsage(input: 1500, cached: 900, output: 260)), sessionID: "s")
        let event = try #require(emitted)
        #expect(event.split == TokenSplit(input: 200, cacheWrite: 0, output: 60, cacheRead: 300))
        #expect(abs(event.timestamp.timeIntervalSince(now.addingTimeInterval(60))) < 0.001)
    }

    @Test func identicalRepeatIsSkipped() throws {
        var tracker = CodexBurnTracker()
        let total = codexUsage(input: 1000, cached: 600, output: 200)
        _ = tracker.ingest(try count(at: 0, total: total), sessionID: "s")
        let repeated = tracker.ingest(try count(at: 5, total: total), sessionID: "s")
        #expect(repeated == nil)
    }

    @Test func decreasingTotalIsAResetThatUsesLastUsage() throws {
        var tracker = CodexBurnTracker()
        _ = tracker.ingest(try count(at: 0, total: codexUsage(input: 5000, cached: 4000, output: 900)), sessionID: "s")
        let reset = try count(at: 60, total: codexUsage(input: 300, cached: 100, output: 40), last: codexUsage(input: 120, cached: 20, output: 10))
        let emitted = tracker.ingest(reset, sessionID: "s")
        let event = try #require(emitted)
        #expect(event.split == TokenSplit(input: 100, cacheWrite: 0, output: 10, cacheRead: 20))

        // Deltas continue from the post-reset total.
        let emittedNext = tracker.ingest(try count(at: 120, total: codexUsage(input: 400, cached: 150, output: 50)), sessionID: "s")
        let next = try #require(emittedNext)
        #expect(next.split == TokenSplit(input: 50, cacheWrite: 0, output: 10, cacheRead: 50))
    }

    @Test func nullInfoYieldsNoBurn() throws {
        var tracker = CodexBurnTracker()
        let event = tracker.ingest(try count(at: 0, total: nil), sessionID: "s")
        #expect(event == nil)
    }

    @Test func modelComesFromTheLatestTurnContext() throws {
        var tracker = CodexBurnTracker()
        let context = tracker.ingest(.turnContext(model: "gpt-5-codex"), sessionID: "s")
        #expect(context == nil)
        let emitted = tracker.ingest(try count(at: 0, total: codexUsage(input: 10, output: 1)), sessionID: "s")
        let event = try #require(emitted)
        #expect(event.model == "gpt-5-codex")
    }
}
