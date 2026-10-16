//
//  MenuBarLabel.swift
//  burnbar
//

import AppKit
import SwiftUI

/// The `MenuBarExtra` label: the heat strip rendered into a non-template image, because the
/// menu bar draws label views as monochrome templates and would drop the lane colours.
///
/// The label is a pure function of observed values: no `TimelineView`, `@State` or `.onChange`,
/// which in a `MenuBarExtra` label re-evaluate on every status-item update and re-rendered the
/// image in an endless loop. Motion comes from `StripAnimationClock`: gauges at or above 90%
/// pulse with a slow opacity wave, and with the Ember motion setting on and live cells in a lane
/// the cells breathe and a lane flashes when its latest bucket grows (`UsageViewState.flashStarts`).
/// The clock's `date` is read only while it is active, so a still strip never re-renders on its own.
struct MenuBarLabel: View {
    let store: UsageStore
    let clock: StripAnimationClock

    private static let pulsePeriod: TimeInterval = 2

    var body: some View {
        let state = store.state
        switch clock.activity {
        case .still:
            StripImage(state: state, pulseOpacity: 1, ember: .still)
        case .pulse:
            StripImage(state: state, pulseOpacity: Self.pulseOpacity(at: clock.date), ember: .still)
        case .ember:
            let date = clock.date
            StripImage(
                state: state,
                pulseOpacity: StripAnimationClock.pulses(state) ? Self.pulseOpacity(at: date) : 1,
                ember: EmberFrame(date: date, isActive: true, flashStarts: state.flashStarts)
            )
        }
    }

    /// The strip as a non-template image at `scale`; nil if rendering fails.
    static func image(for state: UsageViewState, pulseOpacity: Double = 1, ember: EmberFrame = .still,
                      scale: CGFloat) -> NSImage? {
        let renderer = ImageRenderer(content: HeatStripView(state: state, pulseOpacity: pulseOpacity, ember: ember))
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
    let ember: EmberFrame

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let image = MenuBarLabel.image(for: state, pulseOpacity: pulseOpacity, ember: ember, scale: displayScale) {
                Image(nsImage: image)
            } else {
                Text("BURNBAR")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilitySummary)
    }
}
