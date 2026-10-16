//
//  EmberMotion.swift
//  burnbar
//

import Foundation

/// The heat strip's ember motion: live cells breathe with a subtle, deterministic flicker and a
/// lane flashes briefly when new burn lands in its latest bucket. Pure math, so the label only
/// has to supply the clock and the previous snapshot.
nonisolated enum EmberMotion {
    /// Frame step while embers move: about 7 fps keeps the re-rendered menu bar image cheap.
    static let frameInterval: TimeInterval = 0.15
    /// Lowest opacity a breathing cell reaches.
    static let minimumIntensity = 0.7
    /// How long a new-burn flash takes to fade out.
    static let flashDuration: TimeInterval = 0.8
    /// Extra brightness at the start of a flash.
    static let flashBrightness = 0.4

    private static let slowPeriod: TimeInterval = 1.7
    private static let fastPeriod: TimeInterval = 0.7

    /// Motion runs only when the setting is on and Reduce Motion is off.
    static func isAllowed(enabled: Bool, reduceMotion: Bool) -> Bool {
        enabled && !reduceMotion
    }

    /// Whether any lane has a non-empty cell; with none there is nothing to animate.
    static func hasLiveCells(_ lanes: [[Int]]) -> Bool {
        lanes.contains { $0.contains { $0 > 0 } }
    }

    /// A stable pseudo-random offset in 0..<1 for one cell, so neighbours flicker out of step.
    static func cellPhase(provider: Provider, index: Int) -> Double {
        let laneSeed = provider == .claude ? 0 : 17
        let value = sin(Double(index * 31 + laneSeed + 1) * 12.9898) * 43758.5453
        return value - value.rounded(.down)
    }

    /// Opacity multiplier for a live cell at `time`: two out-of-step waves mapped onto
    /// `minimumIntensity...1`.
    static func breath(time: TimeInterval, phase: Double) -> Double {
        let slow = sin(2 * .pi * (time / slowPeriod + phase))
        let fast = sin(2 * .pi * (time / fastPeriod + phase * 1.7))
        let wave = (0.6 * slow + 0.4 * fast + 1) / 2
        return minimumIntensity + (1 - minimumIntensity) * wave
    }

    /// Lanes whose latest bucket holds more tokens than in the previous snapshot. A lane missing
    /// from `previous` (first sight, newly enabled) does not flash, nor does one that shrank
    /// (its bucket rolled over).
    static func flashingLanes(previous: [Provider: Int], current: [Provider: Int]) -> Set<Provider> {
        Set(current.compactMap { provider, heat in
            guard let before = previous[provider], heat > before else { return nil }
            return provider
        })
    }

    /// 1 when a flash starts, easing out to 0 at `flashDuration`; 0 outside it.
    static func flashIntensity(elapsed: TimeInterval) -> Double {
        guard elapsed >= 0, elapsed < flashDuration else { return 0 }
        let remaining = 1 - elapsed / flashDuration
        return remaining * remaining
    }
}

/// One rendered moment of ember motion. `still` (or any inactive frame) draws the strip
/// exactly as without motion.
nonisolated struct EmberFrame: Equatable, Sendable {
    var time: TimeInterval
    var isActive: Bool
    /// Flash intensity per lane, 0...1.
    var flashes: [Provider: Double] = [:]

    static let still = EmberFrame(time: 0, isActive: false)

    /// Opacity multiplier for a cell; 1 for empty cells and inactive frames.
    func cellIntensity(provider: Provider, index: Int, heat: Int) -> Double {
        guard isActive, heat > 0 else { return 1 }
        return EmberMotion.breath(time: time, phase: EmberMotion.cellPhase(provider: provider, index: index))
    }

    /// Flash intensity for a lane; 0 for inactive frames.
    func flash(for provider: Provider) -> Double {
        isActive ? flashes[provider] ?? 0 : 0
    }
}

extension EmberFrame {
    /// The frame at `date`, with flashes that started at `flashStarts`.
    init(date: Date, isActive: Bool, flashStarts: [Provider: Date]) {
        self.init(
            time: date.timeIntervalSinceReferenceDate,
            isActive: isActive,
            flashes: flashStarts.mapValues { EmberMotion.flashIntensity(elapsed: date.timeIntervalSince($0)) }
        )
    }
}
