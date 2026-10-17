//
//  ProviderCardView.swift
//  burnbar
//

import SwiftUI

/// One provider's cockpit column: name and pace chip, the bordered status strip, the headline
/// (click flips budget and tokens), burndown, spend advice, windows, burn, token mix, models and
/// the turns/sessions footer. Purely presentational.
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
        VStack(alignment: .leading, spacing: 12) {
            CardTitleRow(card: card, lane: lane)
            StatusStrip(status: card.statusLine, instruction: card.instruction)
            HeadlineButton(headline: headline, lane: lane, action: onToggleHeadline)
            if let burndown = card.burndown {
                BurndownChartView(burndown: burndown, lane: lane)
            }
            if let advice = card.spendAdvice {
                Text(Self.sentence(advice))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(card.verdict?.isOverPace == true ? palette.bad : palette.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !card.lines.isEmpty {
                WindowsSection(lines: card.lines, lane: lane)
            }
            BurnSection(card: card, lane: lane, windowLabel: windowLabel, window: window)
            TokenMixSection(split: card.split, lane: lane)
            if !card.topModels.isEmpty {
                ModelSection(models: card.topModels, share: card.share(of:), lane: lane)
            }
            Text("\(card.turns) turns · \(card.sessions) sessions")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(palette.secondary)
                .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitBox(border: lane, glow: glow.map { $0.isAlarm ? palette.bad : lane }, intensity: glow?.intensity ?? 0)
    }

    /// Lowercases the first letter: captions read as sentences, not titles.
    static func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}

private extension Verdict {
    var isOverPace: Bool { self == .over || self == .wayOver }
}

/// Provider name in its lane colour, account, stale tag and pace chip.
private struct CardTitleRow: View {
    let card: ProviderCard
    let lane: Color

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(card.provider.displayName.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(lane)
            if let account = card.accountLabel {
                Text(account)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            if card.isStale {
                Text("STALE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(palette.warn)
                    .accessibilityLabel("limits are stale")
            }
            if let verdict = card.verdict {
                VerdictBadge(verdict: verdict)
            }
        }
    }
}

/// The pace chip, an outlined capsule: ON TRACK green, AT PACE grey, OVER amber, WAY OVER red.
struct VerdictBadge: View {
    let verdict: Verdict

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        let tint = palette.verdict(verdict)
        Text(verdict.title)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.08)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.7), lineWidth: 1))
            .accessibilityLabel("Verdict: \(verdict.title.lowercased())")
    }
}

/// "BANKED 51%  3d 13h in the bank" in one bordered strip tinted by its tone.
private struct StatusStrip: View {
    let status: CardStatus
    let instruction: String

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        let tint = palette.tone(status.tone)
        let shape = RoundedRectangle(cornerRadius: 3)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(status.title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(tint)
                .lineLimit(1)
                .layoutPriority(1)
            Text(status.detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(shape.fill(status.tone == .neutral ? Color.clear : tint.opacity(0.06)))
        .overlay(shape.strokeBorder(status.tone == .neutral ? palette.border : tint.opacity(0.5), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.title.lowercased()), \(status.detail). \(instruction)")
    }
}

/// The big number in the lane colour with a two-line caption; clicking flips budget and tokens.
private struct HeadlineButton: View {
    let headline: CardHeadline
    let lane: Color
    let action: () -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Text(headline.value)
                    .font(.system(size: 30, weight: .medium, design: .monospaced))
                    .foregroundStyle(lane)
                    .lineLimit(1)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 2) {
                    Text(headline.caption)
                        .font(.system(size: 11, design: .monospaced))
                    if let detail = headline.detail {
                        Text(detail)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(palette.secondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(headline.mode == .budget ? "⇄ tokens" : "⇄ budget")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(headline.mode == .budget ? "Show tokens" : "Show budget")
        .accessibilityLabel("\(headline.value) \(headline.caption)")
        .accessibilityHint("Switches the headline between budget and tokens")
    }
}

/// Each limit row: label, reset and share on one line, then a flat gauge with the even-pace tick.
private struct WindowsSection: View {
    let lines: [LimitLine]
    let lane: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(lines) { LimitLineView(line: $0, lane: lane) }
        }
    }
}

private struct LimitLineView: View {
    let line: LimitLine
    let lane: Color

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(line.label)
                    .font(.system(size: 11, design: .monospaced))
                Spacer()
                Text(line.resetText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                    .help(line.isProjectedReset
                        ? "Assumed: the reported reset passed, so a new window started"
                        : "resets \(line.resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                Text(line.percentText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(lane)
                    .frame(minWidth: 34, alignment: .trailing)
            }
            UsageBar(percent: line.percent ?? 0, color: lane, tick: line.elapsed)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.accessibilityLabel)
    }
}

/// Burn now, over the last hour and over the window, with a histogram of the strip buckets.
private struct BurnSection: View {
    let card: ProviderCard
    let lane: Color
    let windowLabel: String
    let window: TimeInterval

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Burn · tokens / min")
            HStack(alignment: .top, spacing: 20) {
                StatColumn(label: "Now", value: card.rate5mText, color: lane)
                StatColumn(label: "1h", value: card.rate60mText)
                StatColumn(label: windowLabel.replacingOccurrences(of: " ", with: ""), value: card.averageRateText(window: window))
            }
            if card.buckets.contains(where: { $0 > 0 }) {
                BurnHistogram(provider: card.provider, buckets: card.buckets)
            } else {
                Text("no burn in the last \(windowLabel)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondary)
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
                    .frame(height: heat > 0 ? max(4, 40 * Double(heat) / Double(max(hottest, 1))) : 1)
            }
        }
        .frame(height: 40, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// How much came from the cache (label row and a share bar), then input, cache write and output.
private struct TokenMixSection: View {
    let split: TokenSplit
    let lane: Color

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Token mix")
                Spacer()
                if let share = split.cacheReadShare {
                    Text("cache read \(CockpitFormat.tokens(split.cacheRead)) · \(CockpitFormat.percent(share)) of input")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(lane)
                        .lineLimit(1)
                }
            }
            UsageBar(percent: split.cacheReadShare ?? 0, color: lane, height: 5)
            Text("in \(CockpitFormat.tokens(split.input)) · cache-write \(CockpitFormat.tokens(split.cacheWrite)) · out \(CockpitFormat.tokens(split.output))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The hottest models: name, a bar relative to the hottest, share and heat.
private struct ModelSection: View {
    let models: [ModelUsage]
    let share: (ModelUsage) -> Double
    let lane: Color

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        let hottest = max(models.map(\.split.heat).max() ?? 1, 1)
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("By model")
            ForEach(models, id: \.model) { model in
                HStack(spacing: 10) {
                    Text(model.model)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: 140, alignment: .leading)
                    UsageBar(percent: Double(model.split.heat) / Double(hottest), color: lane, height: 3)
                    Text(CockpitFormat.percent(share(model)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 34, alignment: .trailing)
                    Text(CockpitFormat.tokens(model.split.heat))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(lane)
                        .frame(width: 50, alignment: .trailing)
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
