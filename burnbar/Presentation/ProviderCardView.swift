//
//  ProviderCardView.swift
//  burnbar
//

import Charts
import SwiftUI

/// One provider's cockpit card: verdict, what to do, limit rows, burndown, burn rates, token mix
/// and the hottest models. Purely presentational.
struct ProviderCardView: View {
    let card: ProviderCard

    private var lane: Color { Color(LanePalette.lane(for: card.provider).warm) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardTitleRow(card: card, lane: lane)
            Text(card.instruction)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
            if let status = card.status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(card.hasError ? Color(LanePalette.error) : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(card.lines) { LimitLineView(line: $0) }
            if let burndown = card.burndown {
                BurndownChartView(burndown: burndown, lane: lane)
            }
            BurnRatesRow(card: card)
            TokenMixView(split: card.split)
            if !card.topModels.isEmpty {
                ModelList(models: card.topModels)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.6)))
        .overlay {
            if card.hasError {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color(LanePalette.error), lineWidth: 1)
            }
        }
    }
}

/// Provider name, account, stale tag and verdict badge.
private struct CardTitleRow: View {
    let card: ProviderCard
    let lane: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(card.title)
                .font(.headline)
                .foregroundStyle(lane)
            if let account = card.accountLabel {
                Text(account)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if card.isStale {
                Text("stale")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("limits are stale")
            }
            if let verdict = card.verdict {
                VerdictBadge(verdict: verdict)
            }
        }
    }
}

struct VerdictBadge: View {
    let verdict: Verdict

    var body: some View {
        Text(verdict.title)
            .font(.caption2.weight(.heavy))
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(verdict.tint)))
            .accessibilityLabel("Verdict: \(verdict.title.lowercased())")
    }
}

/// Label, used share, time to reset ("~" when assumed) and a gauge bar.
private struct LimitLineView: View {
    let line: LimitLine

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.label)
                    .font(.caption)
                Spacer()
                Text(line.percentText)
                    .font(.caption.monospacedDigit().weight(.semibold))
                Text(line.resetText)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help(line.isProjectedReset ? "Assumed: the reported reset passed, so a new window started" : "")
            }
            UsageBar(percent: line.percent ?? 0, color: line.gauge.map { Color($0.tint) } ?? .clear)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.accessibilityLabel)
    }
}

/// A thin horizontal gauge: a track with a fill for the used share.
struct UsageBar: View {
    let percent: Double
    let color: Color

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: 5)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(color)
                        .frame(width: proxy.size.width * min(max(percent, 0), 1))
                }
            }
    }
}

/// Burn rates over the last 5 and 60 minutes, plus window totals.
private struct BurnRatesRow: View {
    let card: ProviderCard

    var body: some View {
        HStack {
            Text("m5 \(card.rate5mText)")
            Text("m60 \(card.rate60mText)")
            Spacer()
            Text("\(card.tokensText) · \(card.turns) turns · \(card.sessions) sessions")
        }
        .font(.caption2.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// Input, cache write, output and cache read as one stacked bar with a legend.
private struct TokenMixView: View {
    let split: TokenSplit

    private var segments: [(kind: String, tokens: Int)] {
        [("Input", split.input), ("Cache write", split.cacheWrite), ("Output", split.output), ("Cache read", split.cacheRead)]
    }

    var body: some View {
        if split.heat + split.cacheRead > 0 {
            Chart(segments, id: \.kind) { segment in
                BarMark(x: .value("Tokens", segment.tokens), y: .value("Mix", "Tokens"))
                    .foregroundStyle(by: .value("Kind", segment.kind))
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(position: .bottom, spacing: 2)
            .frame(height: 34)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Token mix: " + segments.map { "\($0.kind.lowercased()) \(CockpitFormat.tokens($0.tokens))" }.joined(separator: ", "))
        }
    }
}

/// The hottest models by heat.
private struct ModelList: View {
    let models: [ModelUsage]

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(models, id: \.model) { model in
                HStack {
                    Text(model.model)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(CockpitFormat.tokens(model.split.heat))
                        .monospacedDigit()
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Cards") {
    ScrollView {
        VStack(spacing: 10) {
            ForEach(CockpitPreview.cards) { ProviderCardView(card: $0) }
        }
        .padding(12)
    }
    .frame(width: 360, height: 640)
}
#endif
