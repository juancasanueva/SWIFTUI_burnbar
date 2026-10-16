//
//  BurndownChartView.swift
//  burnbar
//

import Charts
import SwiftUI

/// Used share over the window on a dark plot: the even-pace diagonal from 0% at the window
/// start to 100% at the reset (dashed grey), actual samples (solid lane colour, a dot at now),
/// the projection along the fitted rate (dashed lane colour) and a rule at now. VoiceOver reads
/// the burndown's summary.
struct BurndownChartView: View {
    let burndown: Burndown
    let lane: Color

    @Environment(\.cockpitPalette) private var palette

    private enum Series: String {
        case actual = "Actual", ideal = "Ideal", projected = "Projected"
    }

    private var title: String {
        BudgetSummary.name(window: burndown.pace.row.windowDuration, label: burndown.label).uppercased()
            + (burndown.isProjectedReset ? " · NEW WINDOW (ASSUMED)" : "")
    }

    var body: some View {
        Chart {
            line(burndown.ideal, .ideal)
                .foregroundStyle(palette.tertiary)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            if let projected = burndown.projected {
                line(projected, .projected)
                    .foregroundStyle(lane.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            line(burndown.actual, .actual)
                .foregroundStyle(lane)
                .lineStyle(StrokeStyle(lineWidth: 2))
            if let now = burndown.actual.last {
                RuleMark(x: .value("Now", now.t))
                    .foregroundStyle(palette.tertiary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Time", now.t), y: .value("Used", now.percent * 100))
                    .foregroundStyle(lane)
                    .symbolSize(30)
            }
        }
        .chartXScale(domain: burndown.windowStart...burndown.resetsAt)
        .chartYScale(domain: 0...100)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.background(palette.plot)
        }
        .overlay(alignment: .topLeading) {
            Text(title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(palette.secondary)
                .padding(5)
        }
        .frame(height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(burndown.accessibilitySummary)
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
        BurndownChartView(burndown: burndown, lane: Color(LanePalette.claude.accent))
            .padding()
            .frame(width: 400)
            .cockpitChrome()
    }
}
#endif
