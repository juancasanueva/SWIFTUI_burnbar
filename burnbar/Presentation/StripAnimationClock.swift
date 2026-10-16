//
//  StripAnimationClock.swift
//  burnbar
//

import AppKit
import Observation

/// Drives the menu bar strip's motion from outside the `MenuBarExtra` label.
///
/// A `TimelineView` (or `@State`/`.onChange`) inside the label re-evaluates on every status-item
/// update; each evaluation rendered a new image, `setImage` scheduled another update, and the
/// app spun at 100% CPU with the panel unable to open. The label is therefore a pure function of
/// observed values, and this clock is the only thing that changes over time: while the strip
/// moves it ticks `date` at the activity's interval, and when it is still no task runs at all.
@Observable
final class StripAnimationClock {
    /// What, if anything, moves the strip.
    nonisolated enum Activity: Hashable, Sendable {
        case still
        /// Gauges at or above 90% pulse.
        case pulse
        /// Live cells breathe (and gauges pulse with them).
        case ember

        /// The tick step; nil when still.
        var interval: TimeInterval? {
            switch self {
            case .still: nil
            case .pulse: StripAnimationClock.pulseStep
            case .ember: EmberMotion.frameInterval
            }
        }
    }

    /// Pulse frame step: 4 frames a second.
    nonisolated static let pulseStep: TimeInterval = 0.25

    private(set) var activity: Activity = .still
    /// The current frame's instant; changes only while ticking.
    private(set) var date: Date

    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var watcher: Task<Void, Never>?
    @ObservationIgnored private var reduceMotionObserver: NSObjectProtocol?
    /// Bumped each time a ticker starts (a test hook).
    @ObservationIgnored private(set) var tickerID = 0
    /// System Reduce Motion, refreshed when the accessibility display options change.
    private var reduceMotion = false

    init(now: @escaping () -> Date = Date.init) {
        self.now = now
        self.date = now()
    }

    var isTicking: Bool { ticker != nil }

    /// Ember needs the setting and a live cell; pulse needs a gauge at 90%; Reduce Motion stills both.
    nonisolated static func activity(emberEnabled: Bool, hasLiveCells: Bool, pulsing: Bool,
                                     reduceMotion: Bool) -> Activity {
        if EmberMotion.isAllowed(enabled: emberEnabled, reduceMotion: reduceMotion) && hasLiveCells { return .ember }
        if pulsing && !reduceMotion { return .pulse }
        return .still
    }

    nonisolated static func activity(for state: UsageViewState, reduceMotion: Bool) -> Activity {
        activity(
            emberEnabled: state.emberMotion,
            hasLiveCells: EmberMotion.hasLiveCells(state.providers.map(\.lane.buckets)),
            pulsing: pulses(state),
            reduceMotion: reduceMotion
        )
    }

    /// Whether any weekly gauge is high enough to pulse.
    nonisolated static func pulses(_ state: UsageViewState) -> Bool {
        state.providers.contains { $0.weekly.map { GaugeLevel.pulses(percent: $0.percent) } ?? false }
    }

    /// Starts, retimes or stops the ticker; the same activity again changes nothing.
    func setActivity(_ activity: Activity) {
        guard activity != self.activity else { return }
        self.activity = activity
        ticker?.cancel()
        ticker = nil
        guard let interval = activity.interval else { return }
        date = now()
        tickerID += 1
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self else { return }
                self.date = self.now()
            }
        }
    }

    /// Follows the store's state and the system Reduce Motion setting. Live app only: inert runs
    /// and tests never call it, so they start no tasks.
    func follow(_ store: UsageStore) {
        guard watcher == nil else { return }
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
        watcher = Task { [weak self] in
            guard let self else { return }
            for await activity in Observations({ Self.activity(for: store.state, reduceMotion: self.reduceMotion) }) {
                self.setActivity(activity)
            }
        }
    }
}
