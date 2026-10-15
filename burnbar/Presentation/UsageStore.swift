//
//  UsageStore.swift
//  burnbar
//

import Foundation
import Observation

/// Owns the collectors and limit sources and publishes an immutable `UsageViewState`.
///
/// A refresh loop ticks every `collectInterval` (5 s): collectors are read on every tick, limits
/// every `limitsInterval` (300 s) and whenever `refreshLimits(force: true)` is called (panel
/// open). Each limit snapshot is recorded in the sample store so pace can fit a burn rate.
/// Failures never throw: they arrive as `LimitSnapshot.status` and show as status text.
@Observable
final class UsageStore {
    nonisolated enum DefaultsKey {
        static let dismissedAdvice = "advice.dismissed.text"
        static let dismissedSeverity = "advice.dismissed.severity"
    }

    private(set) var state: UsageViewState = .empty

    @ObservationIgnored private let collectors: [Provider: any UsageCollector]
    @ObservationIgnored private let limitSources: [Provider: any LimitsSource]
    @ObservationIgnored private let sampleStore: any LimitSampleRecording
    @ObservationIgnored private let accountReader: any AccountReading
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let collectInterval: Duration
    @ObservationIgnored private let limitsInterval: TimeInterval
    @ObservationIgnored private let now: () -> Date

    @ObservationIgnored private var summary = UsageSummary(bucketStarts: [], lanes: [:])
    @ObservationIgnored private var snapshots: [Provider: LimitSnapshot] = [:]
    @ObservationIgnored private var samples: [Provider: [String: [LimitSample]]] = [:]
    @ObservationIgnored private var accounts: [Provider: AccountInfo] = [:]
    @ObservationIgnored private var lastLimitsRefresh: Date?
    @ObservationIgnored private var isFetchingLimits = false
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(
        collectors: [Provider: any UsageCollector],
        limits: [Provider: any LimitsSource],
        samples: any LimitSampleRecording,
        accounts: any AccountReading,
        defaults: UserDefaults = .standard,
        collectInterval: Duration = .seconds(5),
        limitsInterval: TimeInterval = 300,
        now: @escaping () -> Date = Date.init
    ) {
        self.collectors = collectors
        self.limitSources = limits
        self.sampleStore = samples
        self.accountReader = accounts
        self.defaults = defaults
        self.collectInterval = collectInterval
        self.limitsInterval = limitsInterval
        self.now = now
    }

    /// The real sources: local transcripts, Codex rollout limits, the Claude OAuth endpoint.
    static func live() -> UsageStore {
        let codex = CodexRolloutCollector()
        return UsageStore(
            collectors: [.claude: ClaudeTranscriptCollector(), .codex: codex],
            limits: [.claude: ClaudeLimitsClient(), .codex: codex],
            samples: LimitSampleStore(),
            accounts: AccountReader()
        )
    }

    // MARK: Loop

    /// Starts the refresh loop; a second call does nothing.
    func start() {
        guard loop == nil else { return }
        let interval = collectInterval
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    // MARK: Refresh

    /// One tick: limits when due, then every collector, then a new state.
    func refresh() async {
        let now = now()
        if lastLimitsRefresh.map({ now.timeIntervalSince($0) >= limitsInterval }) ?? true {
            await fetchLimits(now: now, force: false)
        }
        await collect(now: now)
        publish(now: now)
    }

    /// Refreshes limits now; `force` skips the sources' caches (never a rate-limit backoff).
    func refreshLimits(force: Bool) async {
        let now = now()
        await fetchLimits(now: now, force: force)
        publish(now: now)
    }

    /// Hides the current advice until a more severe one comes up; remembered across launches.
    func dismissAdvice() {
        guard let advice = state.advice else { return }
        defaults.set(advice.text, forKey: DefaultsKey.dismissedAdvice)
        defaults.set(advice.severity, forKey: DefaultsKey.dismissedSeverity)
        publish(now: state.updatedAt ?? now())
    }

    private func collect(now: Date) async {
        var events: [UsageEvent] = []
        for provider in Provider.allCases {
            guard let collector = collectors[provider] else { continue }
            events += await collector.events(now: now)
        }
        summary = UsageAggregator.summarize(events, now: now)
    }

    private func fetchLimits(now: Date, force: Bool) async {
        guard !isFetchingLimits else { return }
        isFetchingLimits = true
        defer { isFetchingLimits = false }
        lastLimitsRefresh = now

        accounts[.claude] = accountReader.claude()
        accounts[.codex] = accountReader.codex()
        for provider in Provider.allCases {
            // A nil snapshot means nothing new is known: keep showing the last one.
            guard let source = limitSources[provider],
                  let snapshot = await source.limits(now: now, force: force) else { continue }
            snapshots[provider] = snapshot
            await sampleStore.record(snapshot)
            var rows: [String: [LimitSample]] = [:]
            for row in snapshot.rows {
                rows[row.label] = await sampleStore.samples(provider: provider, label: row.label)
            }
            samples[provider] = rows
        }
    }

    // MARK: State

    private func publish(now: Date) {
        let providers = Provider.allCases.map { providerState($0, now: now) }
        let known = providers.filter { !$0.limits.isEmpty && ($0.fiveHour != nil || $0.weekly != nil) }
        let current = providers
            .filter { $0.lane.rate60m > 0 }
            .max { $0.lane.rate60m < $1.lane.rate60m }?
            .provider
        let advice = known.isEmpty ? nil : AdviceEngine.advise(known.map(\.subscriptionPace), current: current, now: now)

        state = UsageViewState(
            summary: summary,
            providers: providers,
            advice: advice,
            isAdviceDismissed: isDismissed(advice),
            updatedAt: now
        )
    }

    private func providerState(_ provider: Provider, now: Date) -> ProviderState {
        let snapshot = snapshots[provider]
        let rows = snapshot?.rows ?? []
        let limits = rows.map { row in
            LimitRowState(row: row, pace: PaceCalculator.pace(for: row, samples: samples[provider]?[row.label] ?? [], now: now))
        }
        return ProviderState(
            provider: provider,
            lane: summary.lane(provider),
            limits: limits,
            measuredAt: snapshot?.measuredAt,
            status: snapshot == nil ? "No \(provider.title) limits yet" : snapshot?.status,
            isStale: snapshot.map { PaceCalculator.isStale(fetchedAt: $0.measuredAt, refreshInterval: limitsInterval, now: now) } ?? false,
            hasError: snapshot.map { !$0.limitsLive && $0.rows.isEmpty } ?? false,
            account: accounts[provider]
        )
    }

    /// Whether `advice` is covered by a stored dismissal; a more severe advice clears it.
    private func isDismissed(_ advice: Advice?) -> Bool {
        guard let advice, let dismissed = defaults.object(forKey: DefaultsKey.dismissedSeverity) as? Int else { return false }
        guard advice.severity <= dismissed else {
            defaults.removeObject(forKey: DefaultsKey.dismissedAdvice)
            defaults.removeObject(forKey: DefaultsKey.dismissedSeverity)
            return false
        }
        return true
    }
}
