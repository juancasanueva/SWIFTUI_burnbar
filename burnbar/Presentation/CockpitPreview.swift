//
//  CockpitPreview.swift
//  burnbar
//
//  Synthetic cockpit state for SwiftUI previews only.
//

#if DEBUG
import Foundation

nonisolated enum CockpitPreview {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static var header: CockpitHeader { CockpitHeader(state: viewState) }
    static var cards: [ProviderCard] { viewState.cards(now: now) }

    /// Claude over its weekly pace and burning; Codex weekly-only with a restarted week.
    static var viewState: UsageViewState {
        let hour: TimeInterval = 3600, week = 7 * 24 * hour
        let claudeWeekly = LimitRow(label: "Weekly (7-day)", percent: 0.58, resetsAt: now.addingTimeInterval(3 * 24 * hour), windowDuration: week)
        let claudeFive = LimitRow(label: "Session (5-hour)", percent: 0.21, resetsAt: now.addingTimeInterval(3 * hour), windowDuration: 5 * hour)
        let claudeSamples = (0..<12).map { i in
            LimitSample(t: now.addingTimeInterval(-Double(11 - i) * 8 * hour), percent: 0.08 + Double(i) * 0.045)
        }
        let codexWeekly = LimitRow(label: "Weekly (7-day)", percent: 0.12, resetsAt: now.addingTimeInterval(-2 * 24 * hour), windowDuration: week)

        let claudeLane = LaneUsage(
            provider: .claude, buckets: [0, 0, 1200, 5400, 8000, 3000, 0, 0, 9000, 12000, 4000, 2500],
            heat: 45_100, split: TokenSplit(input: 3100, cacheWrite: 22_000, output: 20_000, cacheRead: 410_000),
            byModel: [ModelUsage(model: "claude-opus-4", split: TokenSplit(input: 2000, cacheWrite: 15_000, output: 14_000, cacheRead: 0)),
                      ModelUsage(model: "claude-sonnet-4", split: TokenSplit(input: 1100, cacheWrite: 7000, output: 6000, cacheRead: 0))],
            turns: 84, sessions: 3, rate5m: 820, rate60m: 310
        )
        let providers = [
            state(.claude, rows: [claudeFive, claudeWeekly], samples: ["Weekly (7-day)": claudeSamples], lane: claudeLane,
                  account: AccountInfo(email: "dev@example.com"), isStale: false),
            state(.codex, rows: [codexWeekly], samples: [:], lane: .empty(.codex),
                  account: AccountInfo(email: "dev@example.com"), isStale: true),
        ]
        return UsageViewState(summary: UsageSummary(bucketStarts: [], lanes: [.claude: claudeLane]),
                              providers: providers, advice: .useNext(.codex), isAdviceDismissed: false, updatedAt: now)
    }

    private static func state(_ provider: Provider, rows: [LimitRow], samples: [String: [LimitSample]], lane: LaneUsage,
                              account: AccountInfo, isStale: Bool) -> ProviderState {
        let limits = rows.map { row in
            let pace = PaceCalculator.pace(for: row, samples: samples[row.label] ?? [], now: now)
            return LimitRowState(row: pace?.row ?? row, pace: pace)
        }
        return ProviderState(provider: provider, lane: lane, limits: limits, measuredAt: now, status: nil,
                             isStale: isStale, hasError: false, account: account, samples: samples)
    }
}
#endif
