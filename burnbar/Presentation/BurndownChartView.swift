//
//  BurndownChartView.swift
//  burnbar
//

import Charts
import SwiftUI

/// Used share over the window: actual samples (solid), the ideal straight burn from 0% at the
/// window start to 100% at the reset (dashed grey) and the projection along the fitted rate
/// (dashed lane colour), with a rule at now. VoiceOver reads the burndown's summary.
struct BurndownChartView: View {
    let burndown: Burndown
    let lane: Color

    private enum Series: String {
        case actual = "Actual", ideal = "Ideal", projected = "Projected"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(burndown.label + (burndown.isProjectedReset ? " · new window (assumed)" : ""))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Chart {
                line(burndown.ideal, .ideal)
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                if let projected = burndown.projected {
                    line(projected, .projected)
                        .foregroundStyle(lane.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                line(burndown.actual, .actual)
                    .foregroundStyle(lane)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                if let now = burndown.actual.last {
                    RuleMark(x: .value("Now", now.t))
                        .foregroundStyle(.tertiary)
                        .lineStyle(StrokeStyle(lineWidth: 0.5))
                }
            }
            .chartXScale(domain: burndown.windowStart...burndown.resetsAt)
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisGridLine()
                    AxisValueLabel { Text("\(value.as(Int.self) ?? 0)%") }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: burndown.pace.row.windowDuration > 36 * 3600
                                   ? .dateTime.weekday(.abbreviated) : .dateTime.hour())
                }
            }
            .frame(height: 90)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(burndown.accessibilitySummary)
        }
    }

    /// A line series; `series` keeps the three lines from joining. Points are identified by
    /// position (the series already holds one point per instant).
    private func line(_ points: [BurndownPoint], _ series: Series) -> some ChartContent {
        ForEach(Array(points.enumerated()), id: \.offset) { _, point in
            LineMark(
                x: .value("Time", point.t),
                y: .value("Used", point.percent * 100),
                series: .value("Series", series.rawValue)
            )
        }
    }
}

#if DEBUG
#Preview {
    if let burndown = CockpitPreview.cards.first?.burndown {
        BurndownChartView(burndown: burndown, lane: Color(LanePalette.claude.warm))
            .padding()
            .frame(width: 340)
    }
}
#endif
