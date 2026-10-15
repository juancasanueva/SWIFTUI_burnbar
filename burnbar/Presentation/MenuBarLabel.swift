//
//  MenuBarLabel.swift
//  burnbar
//

import AppKit
import SwiftUI

/// The `MenuBarExtra` label: the heat strip rendered into a non-template image, because the
/// menu bar draws label views as monochrome templates and would drop the lane colours.
///
/// Gauges at or above 90% pulse with a slow opacity wave (re-rendered 4 times a second, only
/// while pulsing); with Reduce Motion on they stay still.
struct MenuBarLabel: View {
    let store: UsageStore

    private static let pulseStep: TimeInterval = 0.25
    private static let pulsePeriod: TimeInterval = 2

    var body: some View {
        let state = store.state
        if Self.pulses(state), !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            TimelineView(.periodic(from: .now, by: Self.pulseStep)) { context in
                StripImage(state: state, pulseOpacity: Self.pulseOpacity(at: context.date))
            }
        } else {
            StripImage(state: state, pulseOpacity: 1)
        }
    }

    private static func pulses(_ state: UsageViewState) -> Bool {
        state.providers.contains { $0.weekly.map { GaugeLevel.pulses(percent: $0.percent) } ?? false }
    }

    /// The strip as a non-template image at `scale`; nil if rendering fails.
    static func image(for state: UsageViewState, pulseOpacity: Double = 1, scale: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: HeatStripView(state: state, pulseOpacity: pulseOpacity))
        renderer.scale = scale
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = false
        return image
    }

    /// 0.5...1 along a cosine wave.
    private static func pulseOpacity(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: pulsePeriod) / pulsePeriod
        return 0.75 + 0.25 * cos(phase * 2 * .pi)
    }
}

private struct StripImage: View {
    let state: UsageViewState
    let pulseOpacity: Double

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image = MenuBarLabel.image(for: state, pulseOpacity: pulseOpacity, scale: displayScale) {
                Image(nsImage: image)
            } else {
                Text("BURNBAR")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilitySummary)
    }
}
