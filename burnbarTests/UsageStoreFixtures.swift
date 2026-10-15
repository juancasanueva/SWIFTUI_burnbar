//
//  UsageStoreFixtures.swift
//  burnbarTests
//
//  In-memory doubles for the usage store's collectors, limit sources, sample store and accounts.
//  Mutex-backed classes rather than actors, like `StubTransport`.
//

import Foundation
import Synchronization
@testable import burnbar

final class StubCollector: UsageCollector {
    private let state: Mutex<(events: [UsageEvent], calls: Int)>

    init(_ events: [UsageEvent] = []) { state = Mutex((events, 0)) }

    var calls: Int { state.withLock { $0.calls } }
    func set(_ events: [UsageEvent]) { state.withLock { $0.events = events } }

    func events(now: Date) async -> [UsageEvent] {
        state.withLock { state in
            state.calls += 1
            return state.events
        }
    }
}

final class StubLimits: LimitsSource {
    private struct State {
        var snapshot: LimitSnapshot?
        var forces: [Bool] = []
    }

    private let state: Mutex<State>

    init(_ snapshot: LimitSnapshot? = nil) { state = Mutex(State(snapshot: snapshot)) }

    /// The `force` flag of every call, in order.
    var forces: [Bool] { state.withLock { $0.forces } }
    func set(_ snapshot: LimitSnapshot?) { state.withLock { $0.snapshot = snapshot } }

    func limits(now: Date) async -> LimitSnapshot? {
        await limits(now: now, force: false)
    }

    func limits(now: Date, force: Bool) async -> LimitSnapshot? {
        state.withLock { state in
            state.forces.append(force)
            return state.snapshot
        }
    }
}

final class StubSampleStore: LimitSampleRecording {
    private let state = Mutex<(recorded: [LimitSnapshot], samples: [String: [LimitSample]])>(([], [:]))

    var recorded: [LimitSnapshot] { state.withLock { $0.recorded } }

    func seed(_ provider: Provider, label: String, _ samples: [LimitSample]) {
        state.withLock { $0.samples["\(provider.rawValue)|\(label)"] = samples }
    }

    func record(_ snapshot: LimitSnapshot) async {
        state.withLock { $0.recorded.append(snapshot) }
    }

    func samples(provider: Provider, label: String) async -> [LimitSample] {
        state.withLock { $0.samples["\(provider.rawValue)|\(label)"] ?? [] }
    }
}

struct StubAccounts: AccountReading {
    var claudeAccount: AccountInfo? = AccountInfo(email: "dev@example.com")
    var codexAccount: AccountInfo? = .apiKey

    func claude() -> AccountInfo? { claudeAccount }
    func codex() -> AccountInfo? { codexAccount }
}

/// A snapshot with a 5-hour and a weekly row, each `elapsed` (0..1) through its window.
func limitSnapshot(
    _ provider: Provider,
    fiveHour: Double,
    weekly: Double,
    fiveHourElapsed: Double = 0.5,
    weeklyElapsed: Double = 0.5,
    measuredAt: Date = now,
    status: String? = nil,
    live: Bool = true
) -> LimitSnapshot {
    LimitSnapshot(
        provider: provider,
        rows: [
            row("Session (5-hour)", percent: fiveHour, elapsed: fiveHourElapsed, window: fiveHours),
            row("Weekly (7-day)", percent: weekly, elapsed: weeklyElapsed),
        ],
        measuredAt: measuredAt,
        status: status,
        limitsLive: live
    )
}

/// A fresh, empty defaults suite; call `removePersistentDomain` when done.
func makeTestDefaults() -> (UserDefaults, String) {
    let name = "burnbar-tests-\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}
