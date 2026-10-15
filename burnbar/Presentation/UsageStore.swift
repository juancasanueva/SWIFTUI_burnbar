//
//  UsageStore.swift
//  burnbar
//

import Foundation
import Observation

/// Owns the collectors and limit sources and publishes an immutable `UsageViewState`.
///
/// Two independent loops tick every `collectInterval` (5 s): one reads the collectors, the other
/// fetches limits when `limitsInterval` (300 s) has passed. A slow limits fetch (a pending
/// Keychain prompt, a hung request) therefore never freezes the heat lanes. Limits are also
/// fetched by `refreshLimits(force: true)` (panel open); a force issued while a fetch is in
/// flight runs once more after it. Each limit snapshot is recorded in the sample store so pace
/// can fit a burn rate. Failures never throw: they arrive as `LimitSnapshot.status` and show as
/// status text. An inert store (`isInert`) ignores every loop and refresh.
@Observable
final class UsageStore {
    nonisolated enum DefaultsKey {
        static let dismissedIdentity = "advice.dismissed.identity"
        static let dismissedSeverity = "advice.dismissed.severity"
    }

    private(set) var state: UsageViewState = .empty
    /// Hosted tests and UI launch tests: no loop, no fetch, no collection, no account read.
    let isInert: Bool

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
    @ObservationIgnored private var hasFetchedLimits = false
    @ObservationIgnored private var limitsFetch: Task<Void, Never>?
    @ObservationIgnored private var pendingForce = false
    /// Callers currently waiting on an in-flight limits fetch (a test hook for coalescing).
    @ObservationIgnored private(set) var limitsFetchWaiters = 0
    @ObservationIgnored private var loops: [Task<Void, Never>] = []

    init(
        collectors: [Provider: any UsageCollector],
        limits: [Provider: any LimitsSource],
        samples: any LimitSampleRecording,
        accounts: any AccountReading,
        defaults: UserDefaults = .standard,
        collectInterval: Duration = .seconds(5),
        limitsInterval: TimeInterval = 300,
        now: @escaping () -> Date = Date.init,
        isInert: Bool = false
    ) {
        self.collectors = collectors
        self.limitSources = limits
        self.sampleStore = samples
        self.accountReader = accounts
        self.defaults = defaults
        self.collectInterval = collectInterval
        self.limitsInterval = limitsInterval
        self.now = now
        self.isInert = isInert
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

    /// A store with no sources that ignores every refresh: nothing touches the Keychain, account
    /// files, transcripts or the network.
    static func inert() -> UsageStore {
        UsageStore(collectors: [:], limits: [:], samples: NoSampleStore(), accounts: NoAccounts(), isInert: true)
    }

    // MARK: Loop

    /// Starts the collection and limits loops; a second call, or any call when inert, does nothing.
    func start() {
        guard !isInert, loops.isEmpty else { return }
        loops = [
            tickLoop { await $0.collectUsage() },
            tickLoop { await $0.refreshLimitsIfDue() },
        ]
    }

    func stop() {
        loops.forEach { $0.cancel() }
        loops = []
    }

    private func tickLoop(_ tick: @escaping (UsageStore) async -> Void) -> Task<Void, Never> {
        let interval = collectInterval
        return Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await tick(self)
                try? await Task.sleep(for: interval)
            }
        }
    }

    // MARK: Refresh

    /// One tick of both loops: usage is collected and published without waiting for limits,
    /// which are fetched alongside when due. Returns once both are done.
    func refresh() async {
        guard !isInert else { return }
        async let limits: Void = refreshLimitsIfDue()
        await collectUsage()
        await limits
    }

    /// Reads every collector and publishes a new state.
    func collectUsage() async {
        guard !isInert else { return }
        let now = now()
        await collect(now: now)
        publish(now: now)
    }

    /// Fetches limits when `limitsInterval` has passed and no fetch is in flight.
    func refreshLimitsIfDue() async {
        guard !isInert, limitsFetch == nil else { return }
        if let last = lastLimitsRefresh, now().timeIntervalSince(last) < limitsInterval { return }
        await fetchLimits(force: false)
    }

    /// Refreshes limits now; `force` skips the sources' caches (never a rate-limit backoff).
    /// While a fetch is in flight, a forced call queues one follow-up fetch and waits for it;
    /// an unforced call just waits for the running fetch.
    func refreshLimits(force: Bool) async {
        guard !isInert else { return }
        await fetchLimits(force: force)
    }

    /// Hides the current advice while it persists at the same or lower severity; remembered
    /// across launches.
    func dismissAdvice() {
        guard let advice = state.advice else { return }
        defaults.set(advice.identity, forKey: DefaultsKey.dismissedIdentity)
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

    private func fetchLimits(force: Bool) async {
        if let running = limitsFetch {
            if force { pendingForce = true }
            limitsFetchWaiters += 1
            await running.value
            limitsFetchWaiters -= 1
            return
        }
        let fetch = Task {
            var force = force
            while true {
                let now = self.now()
                await self.fetchLimitsOnce(now: now, force: force)
                self.publish(now: now)
                guard self.pendingForce else { break }
                self.pendingForce = false
                force = true
            }
            self.limitsFetch = nil
        }
        limitsFetch = fetch
        await fetch.value
    }

    private func fetchLimitsOnce(now: Date, force: Bool) async {
        lastLimitsRefresh = now
        defer { hasFetchedLimits = true }

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
            let pace = PaceCalculator.pace(for: row, samples: samples[provider]?[row.label] ?? [], now: now)
            // After a passed reset the pace carries the restarted window; show that one.
            return LimitRowState(row: pace?.row ?? row, pace: pace)
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

    /// Whether `advice` is covered by the stored dismissal: the same advice (kind and provider)
    /// at the same or lower severity. A different or more severe advice clears the dismissal, and
    /// so does no advice from live limits. No advice because nothing is known yet (before the first
    /// fetch) or because a refresh failed keeps the dismissal: a transient failure must not bring
    /// a dismissed chip back.
    private func isDismissed(_ advice: Advice?) -> Bool {
        guard let advice else {
            if limitsAreLive { clearDismissal() }
            return false
        }
        guard let identity = defaults.string(forKey: DefaultsKey.dismissedIdentity),
              let severity = defaults.object(forKey: DefaultsKey.dismissedSeverity) as? Int else { return false }
        guard advice.identity == identity, advice.severity <= severity else {
            clearDismissal()
            return false
        }
        return true
    }

    /// Limits were fetched and every provider's latest snapshot is live (not last-known values).
    private var limitsAreLive: Bool {
        hasFetchedLimits && !snapshots.isEmpty && snapshots.values.allSatisfy(\.limitsLive)
    }

    private func clearDismissal() {
        defaults.removeObject(forKey: DefaultsKey.dismissedIdentity)
        defaults.removeObject(forKey: DefaultsKey.dismissedSeverity)
    }
}

/// The inert store's sample store: records nothing.
private nonisolated struct NoSampleStore: LimitSampleRecording {
    func record(_ snapshot: LimitSnapshot) async {}
    func samples(provider: Provider, label: String) async -> [LimitSample] { [] }
}

/// The inert store's account reader: reads nothing.
private nonisolated struct NoAccounts: AccountReading {
    func claude() -> AccountInfo? { nil }
    func codex() -> AccountInfo? { nil }
}
