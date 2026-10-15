//
//  ClaudeTranscriptParser.swift
//  burnbar
//

import Foundation

/// One revision of a Claude assistant message; transcripts rewrite a message as it streams.
nonisolated struct ClaudeTurn: Hashable, Sendable {
    let messageID: String
    let event: UsageEvent

    /// All four counts, cache reads included; the revision with the largest total wins.
    var totalTokens: Int { event.split.heat + event.split.cacheRead }
}

/// Parses Claude Code transcript lines (`~/.claude/projects/**/*.jsonl`). Pure, no I/O.
nonisolated enum ClaudeTranscriptParser {
    /// Model prefixes that belong to other lanes (Kimi through a Claude-compatible endpoint).
    static let excludedModelPrefixes = ["kimi", "moonshot"]

    private static let usageMarker = Data(#""usage""#.utf8)

    static func turn(from line: String, fallbackSessionID: String) -> ClaudeTurn? {
        turn(from: Data(line.utf8), fallbackSessionID: fallbackSessionID)
    }

    /// The turn on `line`, or nil for lines without a usable usage record: malformed JSON,
    /// no message id or usage, an unreadable timestamp, an excluded model, or zero tokens
    /// (synthetic turns). `fallbackSessionID` is used when the line has no `sessionId`.
    static func turn(from line: Data, fallbackSessionID: String) -> ClaudeTurn? {
        guard line.range(of: usageMarker) != nil,
              let record = try? JSONDecoder().decode(Record.self, from: line),
              let message = record.message, let id = message.id, let usage = message.usage,
              let stamp = record.timestamp, let timestamp = TranscriptTimestamp.date(from: stamp) else { return nil }

        let model = message.model ?? "unknown"
        let lowered = model.lowercased()
        guard !excludedModelPrefixes.contains(where: { lowered.hasPrefix($0) }) else { return nil }

        let split = TokenSplit(
            input: usage.inputTokens ?? 0,
            cacheWrite: usage.cacheCreationInputTokens ?? 0,
            output: usage.outputTokens ?? 0,
            cacheRead: usage.cacheReadInputTokens ?? 0
        )
        guard split.heat + split.cacheRead > 0 else { return nil }

        let event = UsageEvent(
            provider: .claude,
            timestamp: timestamp,
            model: model,
            split: split,
            sessionID: record.sessionId ?? fallbackSessionID
        )
        return ClaudeTurn(messageID: id, event: event)
    }

    /// One turn per message id, keeping the revision with the largest token total.
    static func deduplicated(_ turns: [ClaudeTurn]) -> [ClaudeTurn] {
        var byID: [String: ClaudeTurn] = [:]
        for turn in turns { merge(turn, into: &byID) }
        return byID.values.sorted { $0.event.timestamp < $1.event.timestamp }
    }

    /// Stores `turn` unless a revision with at least as many tokens is already kept.
    static func merge(_ turn: ClaudeTurn, into byID: inout [String: ClaudeTurn]) {
        if let kept = byID[turn.messageID], kept.totalTokens >= turn.totalTokens { return }
        byID[turn.messageID] = turn
    }

    // Only the fields burnbar needs; everything else on the line is ignored.
    private struct Record: Decodable {
        let timestamp: String?
        let sessionId: String?
        let message: Message?
    }

    private struct Message: Decodable {
        let id: String?
        let model: String?
        let usage: Usage?
    }

    private struct Usage: Decodable {
        let inputTokens: Int?
        let cacheCreationInputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cacheCreationInputTokens = "cache_creation_input_tokens"
            case outputTokens = "output_tokens"
            case cacheReadInputTokens = "cache_read_input_tokens"
        }
    }
}
