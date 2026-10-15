//
//  HeatStripView.swift
//  burnbar
//

import SwiftUI

/// The bar's compact strip: Claude's weekly gauge, one lane of 12 heat cells per provider
/// (Claude above Codex), Codex's weekly gauge, then the advice chip when there is one.
struct HeatStripView: View {
    let state: UsageViewState
    /// Opacity of gauges at or above 90% used, driven by the label's pulse; 1 when still.
    var pulseOpacity: Double = 1

    static let height: CGFloat = 18

    /// Gauge fill for a used share, clamped to the strip and never thinner than 2 pt.
    static func gaugeFillHeight(percent: Double) -> CGFloat {
        max(2, height * min(max(percent, 0), 1))
    }

    var body: some View {
        HStack(spacing: 3) {
            GaugeTick(pace: state.provider(.claude)?.weekly, pulseOpacity: pulseOpacity)
            VStack(spacing: 2) {
                ForEach(state.providers) { provider in
                    LaneCells(provider: provider, peak: state.summary.peakBucketHeat)
                }
            }
            GaugeTick(pace: state.provider(.codex)?.weekly, pulseOpacity: pulseOpacity)
            if let advice = state.visibleAdvice {
                AdviceChip(text: advice.text)
            }
        }
        .frame(height: Self.height)
        .padding(.horizontal, 1)
    }
}

/// One provider's 12 cells, coloured cold → warm → hot by heat relative to the hottest cell
/// across lanes. A failed lane is solid red.
private struct LaneCells: View {
    let provider: ProviderState
    let peak: Int

    private static let cell = CGSize(width: 4, height: 7)
    private static let spacing: CGFloat = 1

    var body: some View {
        let buckets = provider.lane.buckets
        if provider.hasError {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color(LanePalette.error))
                .frame(width: Self.cell.width * CGFloat(buckets.count) + Self.spacing * CGFloat(buckets.count - 1),
                       height: Self.cell.height)
        } else {
            let lane = LanePalette.lane(for: provider.provider)
            HStack(spacing: Self.spacing) {
                ForEach(buckets.indices, id: \.self) { index in
                    let heat = buckets[index]
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(lane.color(heat: heat, max: peak)))
                        .opacity(heat > 0 ? 1 : 0.45)
                        .frame(width: Self.cell.width, height: Self.cell.height)
                }
            }
        }
    }
}

/// A vertical weekly gauge filled from the bottom: green, yellow from 75%, red from 90%.
/// An unknown weekly limit shows only the track.
private struct GaugeTick: View {
    let pace: Pace?
    let pulseOpacity: Double

    var body: some View {
        let percent = pace?.percent ?? 0
        ZStack(alignment: .bottom) {
            Capsule().fill(Color.gray.opacity(0.35))
            if let pace {
                Capsule()
                    .fill(Self.color(pace.gauge))
                    .frame(height: HeatStripView.gaugeFillHeight(percent: percent))
                    .opacity(GaugeLevel.pulses(percent: percent) ? pulseOpacity : 1)
            }
        }
        .frame(width: 3, height: HeatStripView.height)
    }

    private static func color(_ level: GaugeLevel) -> Color {
        switch level {
        case .green: Color(RGBHex(0x34C759))
        case .yellow: Color(RGBHex(0xFFCC00))
        case .red: Color(LanePalette.error)
        }
    }
}

private struct AdviceChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .heavy, design: .rounded))
            .foregroundStyle(.black)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color(LanePalette.amber)))
    }
}

extension Color {
    init(_ rgb: RGBHex) {
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

#Preview {
    HeatStripView(state: .empty)
        .padding()
}
