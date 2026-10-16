//
//  ProviderCardView.swift
//  burnbar
//

import SwiftUI

/// One provider's cockpit column: title and pace badge, status line, headline (click flips
/// budget and tokens), burndown, spend advice, windows, burn, token mix and models. Purely
/// presentational.
struct ProviderCardView: View {
    let card: ProviderCard
    let headline: CardHeadline
    let glow: CardGlow?
    /// E.g. "6 h": the trailing window the token totals cover.
    let windowLabel: String
    let window: TimeInterval
    let onToggleHeadline: () -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        let lane = palette.lane(card.provider)
        VStack(alignment: .leading, spacing: 10) {
            CardTitleRow(card: card, lane: lane)
            StatusLineView(status: card.statusLine, instruction: card.instruction)
            HeadlineButton(headline: headline, action: onToggleHeadline)
            if let burndown = card.burndown {
                BurndownChartView(burndown: burndown, lane: lane)
            }
            if let advice = card.spendAdvice {
                Text(advice)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !card.lines.isEmpty {
                WindowsSection(lines: card.lines, lane: lane)
            }
            BurnSection(card: card, windowLabel: windowLabel, window: window)
            TokenMixSection(split: card.split)
            if !card.topModels.isEmpty {
                ModelSection(models: card.topModels, lane: lane)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(lane)
                .frame(height: 2)
                .padding(.horizontal, 8)
                .accessibilityHidden(true)
        }
        .cockpitBox(glow: glow.map { $0.isAlarm ? palette.bad : lane }, intensity: glow?.intensity ?? 0)
    }
}

/// Provider name in its lane colour, account, stale tag and pace badge.
private struct CardTitleRow: View {
    let card: ProviderCard
    let lane: Color

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(card.provider.displayName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(lane)
            if let account = card.accountLabel {
                Text(account)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if card.isStale {
                Text("STALE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(palette.warn)
                    .accessibilityLabel("limits are stale")
            }
            if let verdict = card.verdict {
                VerdictBadge(verdict: verdict)
            }
        }
    }
}

/// The pace capsule: ON TRACK green, AT PACE grey, OVER amber, WAY OVER red.
struct VerdictBadge: View {
    let verdict: Verdict

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        let tint = palette.verdict(verdict)
        Text(verdict.title)
            .font(.system(size: 10, weight: .heavy))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.16)))
            .accessibilityLabel("Verdict: \(verdict.title.lowercased())")
    }
}

/// "BANKED 51%" in its tone, the detail below.
private struct StatusLineView: View {
    let status: CardStatus
    let instruction: String

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(status.title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(palette.tone(status.tone))
            Text(status.detail)
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.title.lowercased()), \(status.detail). \(instruction)")
    }
}

/// The big number with its caption; clicking flips between budget and tokens.
private struct HeadlineButton: View {
    let headline: CardHeadline
    let action: () -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(headline.value)
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                VStack(alignment: .leading, spacing: 1) {
                    Text(headline.caption)
                        .font(.system(size: 12))
                    if let detail = headline.detail {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(headline.mode == .budget ? "Show tokens" : "Show budget")
        .accessibilityLabel("\(headline.value) \(headline.caption)")
        .accessibilityHint("Switches the headline between budget and tokens")
    }
}

/// Each limit row: label and share, a gauge with the even-pace tick, and the reset.
private struct WindowsSection: View {
    let lines: [LimitLine]
    let lane: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Windows")
            ForEach(lines) { LimitLineView(line: $0, lane: lane) }
        }
    }
}

private struct LimitLineView: View {
    let line: LimitLine
    let lane: Color

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(line.label)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Text(line.percentText)
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            UsageBar(percent: line.percent ?? 0, color: lane, tick: line.elapsed)
            Text("\(line.isProjectedReset ? "~" : "")resets \(line.resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())) · in \(line.resetIn)")
                .font(.system(size: 10))
                .foregroundStyle(palette.secondary)
                .help(line.isProjectedReset ? "Assumed: the reported reset passed, so a new window started" : "")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.accessibilityLabel)
    }
}

/// Burn now, over the last hour and over the window, with a histogram of the strip buckets.
private struct BurnSection: View {
    let card: ProviderCard
    let windowLabel: String
    let window: TimeInterval

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Burn")
            HStack(spacing: 18) {
                StatColumn(label: "Now", value: card.rate5mText)
                StatColumn(label: "1 hour", value: card.rate60mText)
                StatColumn(label: windowLabel.replacingOccurrences(of: " ", with: ""), value: card.averageRateText(window: window))
            }
            if card.buckets.contains(where: { $0 > 0 }) {
                BurnHistogram(provider: card.provider, buckets: card.buckets)
            } else {
                Text("nothing burned in the last \(windowLabel)")
                    .font(.system(size: 11))
            }
        }
    }
}

/// One bar per strip bucket, coloured along the lane's heat ramp.
private struct BurnHistogram: View {
    let provider: Provider
    let buckets: [Int]

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        let lane = LanePalette.lane(for: provider)
        let hottest = buckets.max() ?? 0
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(buckets.enumerated()), id: \.offset) { _, heat in
                Rectangle()
                    .fill(heat > 0 ? Color(lane.color(heat: heat, max: hottest)) : palette.track)
                    .frame(maxWidth: .infinity)
                    .frame(height: heat > 0 ? max(4, 30 * Double(heat) / Double(max(hottest, 1))) : 2)
            }
        }
        .frame(height: 30, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// Input, cache write and output, plus how much came from the cache.
private struct TokenMixSection: View {
    let split: TokenSplit

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Token mix")
            HStack(spacing: 18) {
                StatColumn(label: "Input", value: CockpitFormat.tokens(split.input))
                StatColumn(label: "Cache write", value: CockpitFormat.tokens(split.cacheWrite))
                StatColumn(label: "Output", value: CockpitFormat.tokens(split.output))
            }
            if let share = split.cacheReadShare {
                Text("cache reads \(CockpitFormat.tokens(split.cacheRead)) · \(CockpitFormat.percent(share)) of everything the model took in")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The hottest models: name, a bar relative to the hottest, and the heat.
private struct ModelSection: View {
    let models: [ModelUsage]
    let lane: Color

    var body: some View {
        let hottest = max(models.map(\.split.heat).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel("By model")
            ForEach(models, id: \.model) { model in
                HStack(spacing: 8) {
                    Text(model.model)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 170, alignment: .leading)
                    UsageBar(percent: Double(model.split.heat) / Double(hottest), color: lane.opacity(0.85))
                    Text(CockpitFormat.tokens(model.split.heat))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .frame(width: 56, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#if DEBUG
#Preview("Cards") {
    HStack(alignment: .top, spacing: 10) {
        ForEach(CockpitPreview.cards) { card in
            ProviderCardView(card: card, headline: card.headline(.budget, windowLabel: "6 h"),
                             glow: CardGlow.glow(for: card, when: .over), windowLabel: "6 h", window: 6 * 3600,
                             onToggleHeadline: {})
                .frame(width: CockpitView.columnWidth)
        }
    }
    .padding(12)
    .cockpitChrome()
}
#endif
