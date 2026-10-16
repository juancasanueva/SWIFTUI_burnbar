//
//  UsageViewState.swift
//  burnbar
//

import Foundation

/// One limit row with its pace. After a passed reset `row` is the restarted window (0% used,
/// projected reset, `pace.isProjectedReset`); `pace` is nil only when the row has no window length.
nonisolated struct LimitRowState: Hashable, Sendable, Identifiable {
    let row: LimitRow
    let pace: Pace?

    var id: String { row.label }
}

/// Everything the bar and panel show about one provider.
nonisolated struct ProviderState: Hashable, Sendable, Identifiable {
    let provider: Provider
    let lane: LaneUsage
    let limits: [LimitRowState]
    /// When the provider measured its limits; nil while none are known.
    let measuredAt: Date?
    /// Why limits are missing or out of date; nil when all is well.
    let status: String?
    /// Limits older than max(15 min, 3 refreshes).
    let isStale: Bool
    /// The latest limits refresh failed and there are no rows to show.
    let hasError: Bool
    let account: AccountInfo?
    /// Recorded used-share samples per limit label, for the burndown chart.
    var samples: [String: [LimitSample]] = [:]

    var id: Provider { provider }

    /// The first 5-hour row's pace.
    var fiveHour: Pace? { pace(window: 5 * 3600) }
    /// The first 7-day row's pace (the plan-wide weekly limit comes first).
    var weekly: Pace? { pace(window: 7 * 24 * 3600) }

    var subscriptionPace: SubscriptionPace {
        SubscriptionPace(provider: provider, fiveHour: fiveHour, weekly: weekly)
    }

    private func pace(window: TimeInterval) -> Pace? {
        limits.first { $0.row.windowDuration == window }?.pace
    }
}

/// An immutable snapshot of the store, published once per tick.
nonisolated struct UsageViewState: Hashable, Sendable {
    let summary: UsageSummary
    /// The enabled providers, in `Provider.allCases` order.
    let providers: [ProviderState]
    /// Nil when no provider has known limits.
    let advice: Advice?
    /// The user dismissed this advice (or a worse one) and it has not got worse since.
    let isAdviceDismissed: Bool
    let updatedAt: Date?
    /// How cards are mapped: account names and 5-hour rows.
    var cardOptions = CardOptions()
    /// Stored advice dismissals ("Warn me again" clears them).
    var dismissedAdviceCount = 0

    var hasDismissedAdvice: Bool { dismissedAdviceCount > 0 }

    static let empty = UsageViewState(
        summary: UsageSummary(bucketStarts: [], lanes: [:]),
        providers: Provider.allCases.map { provider in
            ProviderState(provider: provider, lane: .empty(provider), limits: [], measuredAt: nil,
                          status: nil, isStale: false, hasError: false, account: nil)
        },
        advice: nil,
        isAdviceDismissed: false,
        updatedAt: nil
    )

    func provider(_ provider: Provider) -> ProviderState? {
        providers.first { $0.provider == provider }
    }

    var visibleAdvice: Advice? { isAdviceDismissed ? nil : advice }

    /// The cockpit cards, one per enabled provider, as of `updatedAt`.
    func cards(now: Date) -> [ProviderCard] {
        providers.map { ProviderCard(state: $0, now: updatedAt ?? now, options: cardOptions) }
    }

    var header: CockpitHeader { CockpitHeader(state: self) }

    /// Every provider's status, one per line; nil when all is well.
    var statusText: String? {
        let lines = providers.compactMap(\.status)
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    /// E.g. "Claude 42% weekly, Codex 31% weekly, advice: use Codex next".
    var accessibilitySummary: String {
        var parts = providers.map { state in
            let name = state.provider.title
            if state.hasError { return "\(name) limits unavailable" }
            guard let weekly = state.weekly else { return "\(name) weekly unknown" }
            return "\(name) \(Int((weekly.percent * 100).rounded()))% weekly"
        }
        if let advice = visibleAdvice {
            parts.append("advice: \(advice.spokenText)")
        }
        return parts.joined(separator: ", ")
    }
}

extension Provider {
    /// Title-case name for sentences, e.g. "Claude".
    nonisolated var title: String { rawValue.capitalized }
}

extension Advice {
    /// The chip text as a sentence, e.g. "use Codex next".
    nonisolated var spokenText: String {
        Provider.allCases.reduce(text.lowercased()) { sentence, provider in
            sentence.replacingOccurrences(of: provider.rawValue, with: provider.title)
        }
    }
}
