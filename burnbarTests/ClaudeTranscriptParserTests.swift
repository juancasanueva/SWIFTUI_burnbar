//
//  ClaudeTranscriptParserTests.swift
//  burnbarTests
//

import Foundation
import Testing
@testable import burnbar

struct ClaudeTranscriptParserTests {
    private func parse(_ line: String, fallback: String = "file-session") -> ClaudeTurn? {
        ClaudeTranscriptParser.turn(from: line, fallbackSessionID: fallback)
    }

    @Test func parsesUsageLine() throws {
        let line = claudeLine(id: "msg_1", at: now, input: 100, cacheWrite: 20, output: 30, cacheRead: 400)
        let turn = try #require(parse(line))
        #expect(turn.messageID == "msg_1")
        #expect(turn.event.provider == .claude)
        #expect(turn.event.model == "claude-opus-4")
        #expect(turn.event.split == TokenSplit(input: 100, cacheWrite: 20, output: 30, cacheRead: 400))
        #expect(turn.event.sessionID == "session-a")
        #expect(abs(turn.event.timestamp.timeIntervalSince(now)) < 0.001)
        #expect(turn.totalTokens == 550)
    }

    @Test func keepsFractionalSeconds() throws {
        let line = claudeLine(id: "m", at: now).replacingOccurrences(of: claudeTimestamp(now), with: "2026-10-15T22:21:41.775Z")
        let turn = try #require(parse(line))
        let expected = try Date("2026-10-15T22:21:41Z", strategy: .iso8601).addingTimeInterval(0.775)
        #expect(abs(turn.event.timestamp.timeIntervalSince(expected)) < 0.001)
    }

    @Test func acceptsTimestampWithoutFractionalSeconds() {
        let line = claudeLine(id: "m", at: now).replacingOccurrences(of: claudeTimestamp(now), with: "2026-10-15T22:21:41Z")
        #expect(parse(line) != nil)
    }

    @Test func fallsBackToFileSessionWithoutSessionID() throws {
        let turn = try #require(parse(claudeLine(id: "m", at: now, sessionID: nil), fallback: "abc"))
        #expect(turn.event.sessionID == "abc")
    }

    @Test func missingCacheFieldsCountAsZero() throws {
        let line = #"{"timestamp":"2026-10-15T22:21:41.775Z","message":{"id":"m","model":"claude-sonnet-4","usage":{"input_tokens":7,"output_tokens":3}}}"#
        let turn = try #require(parse(line))
        #expect(turn.event.split == TokenSplit(input: 7, cacheWrite: 0, output: 3, cacheRead: 0))
    }

    @Test(arguments: [
        "",
        "not json",
        #"{"type":"user","message":{"role":"user","content":"what is my usage?"}}"#,   // mentions usage, no usage object
        #"{"timestamp":"2026-10-15T22:21:41.775Z","message":{"model":"claude-opus-4","usage":{"input_tokens":1,"output_tokens":1}}}"#, // no id
        #"{"timestamp":"yesterday","message":{"id":"m","model":"claude-opus-4","usage":{"input_tokens":1,"output_tokens":1}}}"#, // bad date
        #"{"timestamp":"2026-10-15T22:21:41.775Z","message":{"id":"m","model":"claude-opus-4","usage":{"input_tokens":1,"output_tokens":1}"#, // truncated
        #"{"timestamp":"2026-10-15T22:21:41.775Z","message":{"id":"m","model":"claude-opus-4"}}"#, // no usage
    ])
    func rejectsLinesWithoutUsableUsage(line: String) {
        #expect(parse(line) == nil)
    }

    @Test func skipsZeroUsageSyntheticTurns() {
        #expect(parse(claudeLine(id: "m", at: now, model: "<synthetic>", input: 0, output: 0)) == nil)
    }

    @Test(arguments: ["kimi-k2", "Kimi-K2-Instruct", "moonshot-v1-8k"])
    func excludesOutOfScopeModels(model: String) {
        #expect(parse(claudeLine(id: "m", at: now, model: model)) == nil)
    }

    @Test func dedupeKeepsLargestRevision() {
        let lines = [
            claudeLine(id: "a", at: now, input: 10, output: 1),
            claudeLine(id: "b", at: now.addingTimeInterval(5), input: 3, output: 3),
            claudeLine(id: "a", at: now, input: 10, output: 40),
            claudeLine(id: "a", at: now, input: 10, output: 20),   // an older, smaller revision written later
        ]
        let turns = ClaudeTranscriptParser.deduplicated(lines.compactMap { parse($0) })
        #expect(turns.count == 2)
        #expect(turns.first { $0.messageID == "a" }?.event.split.output == 40)
        #expect(turns.first { $0.messageID == "b" }?.totalTokens == 6)
    }
}
