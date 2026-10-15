//
//  CodexRolloutParser.swift
//  burnbar
//

import Foundation

/// Cumulative or per-turn token counts as Codex reports them. Cached input is part of `input`.
nonisolated struct CodexTokenUsage: Hashable, Sendable {
    var input: Int
    var cachedInput: Int
    var cacheWrite: Int
    var output: Int

    /// Burn split: fresh input = input − cached; cached input counts as cache reads.
    var split: TokenSplit {
        TokenSplit(input: max(0, input - cachedInput), cacheWrite: cacheWrite, output: output, cacheRead: cachedInput)
    }

    /// True when any count went down, which only happens when Codex reset its totals.
    func isBelow(_ other: CodexTokenUsage) -> Bool {
        input < other.input || cachedInput < other.cachedInput || cacheWrite < other.cacheWrite || output < other.output
    }

    static func - (lhs: CodexTokenUsage, rhs: CodexTokenUsage) -> CodexTokenUsage {
        CodexTokenUsage(
            input: lhs.input - rhs.input,
            cachedInput: lhs.cachedInput - rhs.cachedInput,
            cacheWrite: lhs.cacheWrite - rhs.cacheWrite,
            output: lhs.output - rhs.output
        )
    }
}

/// One rate-limit window from a `token_count` record.
nonisolated struct CodexRateWindow: Hashable, Sendable {
    /// Used share as Codex writes it, 0-100.
    let usedPercent: Double
    let windowMinutes: Int
    let resetsAt: Date

    var row: LimitRow {
        LimitRow(
            label: LimitRow.label(windowMinutes: windowMinutes),
            percent: usedPercent / 100,
            resetsAt: resetsAt,
            windowDuration: TimeInterval(windowMinutes) * 60
        )
    }
}

/// A `token_count` event: cumulative usage (nil when `info` is null) plus rate limits.
nonisolated struct CodexTokenCount: Hashable, Sendable {
    let timestamp: Date
    let total: CodexTokenUsage?
    let last: CodexTokenUsage?
    let primary: CodexRateWindow?
    let secondary: CodexRateWindow?

    var hasRateLimits: Bool { primary != nil || secondary != nil }
}

/// The rollout lines burnbar cares about.
nonisolated enum CodexRolloutRecord: Hashable, Sendable {
    /// Model in use from here on.
    case turnContext(model: String)
    case tokenCount(CodexTokenCount)
}

/// Parses Codex rollout lines (`~/.codex/sessions/**/rollout-*.jsonl`). Pure, no I/O.
nonisolated enum CodexRolloutParser {
    private static let tokenCountMarker = Data(#""token_count""#.utf8)
    private static let turnContextMarker = Data(#""turn_context""#.utf8)

    /// The record on `line`, or nil for other line types and lines without usable fields.
    static func record(from line: Data) -> CodexRolloutRecord? {
        let isTokenCount = line.range(of: tokenCountMarker) != nil
        guard isTokenCount || line.range(of: turnContextMarker) != nil,
              let raw = try? JSONDecoder().decode(Line.self, from: line) else { return nil }

        if raw.type == "turn_context" {
            guard let model = raw.payload?.model, !model.isEmpty else { return nil }
            return .turnContext(model: model)
        }
        guard raw.type == "event_msg", let payload = raw.payload, payload.type == "token_count",
              let stamp = raw.timestamp, let timestamp = TranscriptTimestamp.date(from: stamp) else { return nil }
        return .tokenCount(CodexTokenCount(
            timestamp: timestamp,
            total: payload.info?.totalTokenUsage?.usage,
            last: payload.info?.lastTokenUsage?.usage,
            primary: payload.rateLimits?.primary?.window,
            secondary: payload.rateLimits?.secondary?.window
        ))
    }

    /// Limit rows of `count`, primary first; nil when it carries no rate limits.
    static func snapshot(from count: CodexTokenCount) -> LimitSnapshot? {
        let rows = [count.primary, count.secondary].compactMap { $0?.row }
        guard !rows.isEmpty else { return nil }
        return LimitSnapshot(provider: .codex, rows: rows, measuredAt: count.timestamp)
    }

    // Only the fields burnbar needs; everything else on the line is ignored.
    private struct Line: Decodable {
        let timestamp: String?
        let type: String?
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let type: String?
        let model: String?
        let info: Info?
        let rateLimits: RateLimits?

        enum CodingKeys: String, CodingKey {
            case type, model, info
            case rateLimits = "rate_limits"
        }
    }

    private struct Info: Decodable {
        let totalTokenUsage: Usage?
        let lastTokenUsage: Usage?

        enum CodingKeys: String, CodingKey {
            case totalTokenUsage = "total_token_usage"
            case lastTokenUsage = "last_token_usage"
        }
    }

    private struct Usage: Decodable {
        let inputTokens: Int?
        let cachedInputTokens: Int?
        let cacheWriteInputTokens: Int?
        let outputTokens: Int?

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case cachedInputTokens = "cached_input_tokens"
            case cacheWriteInputTokens = "cache_write_input_tokens"
            case outputTokens = "output_tokens"
        }

        var usage: CodexTokenUsage {
            CodexTokenUsage(
                input: inputTokens ?? 0,
                cachedInput: cachedInputTokens ?? 0,
                cacheWrite: cacheWriteInputTokens ?? 0,
                output: outputTokens ?? 0
            )
        }
    }

    private struct RateLimits: Decodable {
        let primary: Window?
        let secondary: Window?
    }

    private struct Window: Decodable {
        let usedPercent: Double?
        let windowMinutes: Int?
        let resetsAt: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }

        var window: CodexRateWindow? {
            guard let usedPercent, let windowMinutes, windowMinutes > 0, let resetsAt else { return nil }
            return CodexRateWindow(usedPercent: usedPercent, windowMinutes: windowMinutes, resetsAt: Date(timeIntervalSince1970: resetsAt))
        }
    }
}

/// Turns one rollout file's cumulative totals into burn events. Feed it the file's records in order.
nonisolated struct CodexBurnTracker: Sendable {
    static let fallbackModel = "codex"

    private(set) var model = fallbackModel
    private var lastTotal: CodexTokenUsage?

    /// The burn since the previous total: nil for repeats, null `info`, other records and zero
    /// deltas. A total below the previous one is a reset, whose burn is `last_token_usage`.
    mutating func ingest(_ record: CodexRolloutRecord, sessionID: String) -> UsageEvent? {
        switch record {
        case .turnContext(let model):
            self.model = model
            return nil
        case .tokenCount(let count):
            guard let total = count.total, total != lastTotal else { return nil }
            let delta: CodexTokenUsage
            if let previous = lastTotal {
                delta = total.isBelow(previous) ? (count.last ?? total) : total - previous
            } else {
                delta = total
            }
            lastTotal = total
            let split = delta.split
            guard split.heat + split.cacheRead > 0 else { return nil }
            return UsageEvent(provider: .codex, timestamp: count.timestamp, model: model, split: split, sessionID: sessionID)
        }
    }
}
