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

extension LimitRow {
    /// Display label for a limit window, e.g. 300 min → "Session (5-hour)", 10080 → "Weekly (7-day)".
    static func label(windowMinutes minutes: Int) -> String {
        let day = 24 * 60
        switch minutes {
        case 10080: return "Weekly (7-day)"
        case day: return "Daily (1-day)"
        case ..<day: return "Session (\(length(minutes)))"
        case _ where minutes % day == 0: return "Window (\(minutes / day)-day)"
        default: return "Window (\(length(minutes)))"
        }
    }

    private static func length(_ minutes: Int) -> String {
        minutes % 60 == 0 ? "\(minutes / 60)-hour" : "\(minutes)-minute"
    }
}

/// The limit rows one provider reported at a moment, e.g. from its newest rate-limit record.
nonisolated struct LimitSnapshot: Hashable, Sendable {
    let provider: Provider
    let rows: [LimitRow]
    /// When the provider measured these limits (not when burnbar read them).
    let measuredAt: Date
    /// Why the rows are missing or out of date, e.g. an expired sign-in; nil when all is well.
    let status: String?
    /// False when the rows are the last known values (or none) because the latest refresh failed.
    let limitsLive: Bool

    init(provider: Provider, rows: [LimitRow], measuredAt: Date, status: String? = nil, limitsLive: Bool = true) {
        self.provider = provider
        self.rows = rows
        self.measuredAt = measuredAt
        self.status = status
        self.limitsLive = limitsLive
    }
}
