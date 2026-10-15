//
//  Classification.swift
//  burnbar
//

/// Headline pace verdict from ratio = used / elapsed.
nonisolated enum Verdict: String, Hashable, Sendable {
    case onTrack, atPace, over, wayOver

    /// > 1.5 way over, > 1.05 over, > 0.9 at pace, else on track. Unknown ratio is on track.
    init(ratio: Double?) {
        let r = ratio ?? 0
        self = r > 1.5 ? .wayOver : r > 1.05 ? .over : r > 0.9 ? .atPace : .onTrack
    }

    var title: String {
        switch self {
        case .onTrack: "ON TRACK"
        case .atPace: "AT PACE"
        case .over: "OVER"
        case .wayOver: "WAY OVER"
        }
    }
}

/// Escalation stage: 1 ratio > 1.05, 2 > 1.5, 3 > 2.5, 4 used ≥ 99.5%.
nonisolated enum Stage: Int, Comparable, Hashable, Sendable {
    case calm = 0, over, wayOver, burning, full

    init(ratio: Double?, percent: Double) {
        let r = ratio ?? 0
        if percent >= 0.995 { self = .full }
        else if r > 2.5 { self = .burning }
        else if r > 1.5 { self = .wayOver }
        else if r > 1.05 { self = .over }
        else { self = .calm }
    }

    static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Gauge colour by used share: ≥ 90% red, ≥ 75% yellow, else green.
nonisolated enum GaugeLevel: Hashable, Sendable {
    case green, yellow, red

    init(percent: Double) {
        self = percent >= 0.9 ? .red : percent >= 0.75 ? .yellow : .green
    }

    /// Gauges pulse from 90% used.
    static func pulses(percent: Double) -> Bool { percent >= 0.9 }
}
