//
//  Models.swift
//  burnbar
//
//  Domain layer: pure value models and usage/pace math.
//  No I/O and no SwiftUI; types are nonisolated and Sendable so collectors can use them off-main.
//

import Foundation

nonisolated enum Provider: String, CaseIterable, Codable, Hashable, Sendable {
    case claude
    case codex

    /// Upper-case lane name used in the bar and advice chip.
    var displayName: String { rawValue.uppercased() }
}

/// Token counts of one turn (or a sum of turns).
nonisolated struct TokenSplit: Codable, Hashable, Sendable {
    var input: Int
    var cacheWrite: Int
    var output: Int
    var cacheRead: Int

    static let zero = TokenSplit(input: 0, cacheWrite: 0, output: 0, cacheRead: 0)

    /// Tokens that count as burn. Cache reads are tracked separately and excluded.
    var heat: Int { input + cacheWrite + output }

    static func + (lhs: TokenSplit, rhs: TokenSplit) -> TokenSplit {
        TokenSplit(
            input: lhs.input + rhs.input,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }

    static func += (lhs: inout TokenSplit, rhs: TokenSplit) { lhs = lhs + rhs }
}

/// One deduplicated turn read from a provider transcript.
nonisolated struct UsageEvent: Hashable, Sendable {
    let provider: Provider
    let timestamp: Date
    let model: String
    let split: TokenSplit
    /// Transcript file identity; nil when the source cannot tell sessions apart.
    let sessionID: String?

    init(provider: Provider, timestamp: Date, model: String, split: TokenSplit, sessionID: String? = nil) {
        self.provider = provider
        self.timestamp = timestamp
        self.model = model
        self.split = split
        self.sessionID = sessionID
    }
}

/// One plan limit, e.g. "Session (5-hour)" or "Weekly (7-day)".
nonisolated struct LimitRow: Codable, Hashable, Sendable {
    let label: String
    /// Used share of the limit, 0...1.
    let percent: Double
    let resetsAt: Date
    let windowDuration: TimeInterval
}

/// A persisted observation of a limit's used share, for rate fitting.
nonisolated struct LimitSample: Codable, Hashable, Sendable {
    let t: Date
    let percent: Double
}
