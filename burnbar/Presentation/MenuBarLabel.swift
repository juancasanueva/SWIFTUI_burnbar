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
/// while pulsing). With the Ember motion setting on and live cells in a lane, the image is
/// re-rendered at `EmberMotion.frameInterval` so cells breathe and a lane flashes when its latest
/// bucket grows. With Reduce Motion on everything stays still.
struct MenuBarLabel: View {
    let store: UsageStore

    /// When each lane's latest new-burn flash started.
    @State private var flashStarts: [Provider: Date] = [:]

    private static let pulseStep: TimeInterval = 0.25
    private static let pulsePeriod: TimeInterval = 2

    var body: some View {
        let state = store.state
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let pulsing = Self.pulses(state) && !reduceMotion
        let ember = EmberMotion.isAllowed(enabled: store.settings.emberMotion, reduceMotion: reduceMotion)
            && EmberMotion.hasLiveCells(state.providers.map(\.lane.buckets))
        Group {
            if pulsing || ember {
                TimelineView(.periodic(from: .now, by: ember ? EmberMotion.frameInterval : Self.pulseStep)) { context in
                    StripImage(
                        state: state,
                        pulseOpacity: pulsing ? Self.pulseOpacity(at: context.date) : 1,
                        ember: EmberFrame(date: context.date, isActive: ember, flashStarts: flashStarts)
                    )
                }
            } else {
                StripImage(state: state, pulseOpacity: 1, ember: .still)
            }
        }
        .onChange(of: Self.latestHeat(state)) { previous, current in
            let now = Date()
            for provider in EmberMotion.flashingLanes(previous: previous, current: current) {
                flashStarts[provider] = now
            }
        }
    }

    /// Each healthy lane's newest bucket, compared across snapshots to detect new burn.
    private static func latestHeat(_ state: UsageViewState) -> [Provider: Int] {
        Dictionary(uniqueKeysWithValues: state.providers.compactMap { provider in
            guard !provider.hasError, let latest = provider.lane.buckets.last else { return nil }
            return (provider.provider, latest)
        })
    }

    private static func pulses(_ state: UsageViewState) -> Bool {
        state.providers.contains { $0.weekly.map { GaugeLevel.pulses(percent: $0.percent) } ?? false }
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
