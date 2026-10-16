//
//  CockpitDisplay.swift
//  burnbar
//
//  Pure display decisions for the cockpit: a card's status line, headline (budget or tokens),
//  spend advice and glow, and the advice banner. Views only lay these out.
//

import Foundation

/// How a status line is coloured.
nonisolated enum CardTone: Hashable, Sendable {
    case good, warn, bad, neutral
}

/// The bold status line under a card's title and its smaller detail, e.g.
/// "BANKED 51%" / "3d 13h in the bank".
nonisolated struct CardStatus: Hashable, Sendable {
    let title: String
    let detail: String
    let tone: CardTone

    init(title: String, detail: String, tone: CardTone) {
        self.title = title
        self.detail = detail
        self.tone = tone
    }

    /// Same order as `ProviderCard.instruction`: spent, 5-hour nearly out, over pace, banked, on pace.
    init(headline: Pace?, fiveHour: Pace?, status: String?, hasError: Bool, now: Date) {
        guard let pace = headline else {
            self.init(title: "NO PLAN READING", detail: status ?? "showing tokens only", tone: hasError ? .bad : .neutral)
            return
        }
        let resetIn = CockpitFormat.duration(pace.row.resetsAt.timeIntervalSince(now))
        if pace.percent >= AdviceEngine.weeklyFull {
            self.init(title: "BACK AT THE RESET", detail: "in \(resetIn)", tone: .bad)
        } else if let five = fiveHour, five.percent >= AdviceEngine.blockedFiveHour {
            let back = CockpitFormat.duration(five.row.resetsAt.timeIntervalSince(now))
            self.init(title: "COME BACK IN \(back)", detail: "5-hour nearly out", tone: .bad)
        } else if pace.isOver {
            if let back = pace.backOnPaceAt, back < pace.row.resetsAt {
                self.init(title: "COME BACK IN \(CockpitFormat.duration(back.timeIntervalSince(now)))",
                          detail: "if you stop now", tone: .warn)
            } else {
                self.init(title: "BACK AT THE RESET", detail: "in \(resetIn)", tone: .warn)
            }
        } else if pace.banked >= AdviceEngine.minimumBanked {
            let bankedTime = CockpitFormat.duration(pace.banked * pace.row.windowDuration)
            self.init(title: "BANKED \(CockpitFormat.percent(pace.banked))", detail: "\(bankedTime) in the bank", tone: .good)
        } else {
            self.init(title: "ON PACE", detail: "spend evenly and it lasts", tone: .neutral)
        }
    }
}

/// The spent share of a card's burndown row, what to call that budget and when it resets.
nonisolated struct BudgetSummary: Hashable, Sendable {
    let spent: Double
    /// E.g. "weekly", "5-hour", "monthly".
    let name: String
    let resetIn: String

    init(pace: Pace, now: Date) {
        spent = pace.percent
        name = Self.name(window: pace.row.windowDuration, label: pace.row.label)
        resetIn = CockpitFormat.duration(pace.row.resetsAt.timeIntervalSince(now))
    }

    static func name(window: TimeInterval, label: String) -> String {
        let hours = Int((window / 3600).rounded())
        switch hours {
        case 5: return "5-hour"
        case 24: return "daily"
        case 7 * 24: return "weekly"
        case 28 * 24...31 * 24: return "monthly"
        default: return label.lowercased()
        }
    }
}

/// A card's big number: the spent budget share, or the window's tokens.
nonisolated struct CardHeadline: Hashable, Sendable {
    /// The mode actually shown: budget falls back to tokens without a known limit.
    let mode: HeadlineMode
    /// E.g. "10%", "623K".
    let value: String
    /// E.g. "of weekly budget spent", "tokens · last 6 h · 201 turns · 6 sessions".
    let caption: String
    /// E.g. "10.4M tokens · resets in 6d 15h"; nil in tokens mode.
    let detail: String?
}

/// A card's outer glow: how strong, and whether it is an alarm (red) or the lane colour.
nonisolated struct CardGlow: Hashable, Sendable {
    let intensity: Double
    let isAlarm: Bool

    /// over: over pace (way over glows full); burning: tokens moved in the last 5 minutes;
    /// spent: scales with the budget spent (alarm from 90%); never: no glow.
    static func glow(for card: ProviderCard, when: GlowWhen) -> CardGlow? {
        switch when {
        case .never:
            return nil
        case .over:
            switch card.verdict {
            case .wayOver: return CardGlow(intensity: 1, isAlarm: true)
            case .over: return CardGlow(intensity: 0.6, isAlarm: true)
            default: return nil
            }
        case .burning:
            return card.rate5m > 0 ? CardGlow(intensity: 0.8, isAlarm: false) : nil
        case .spent:
            guard let spent = card.budget?.spent, spent >= 0.05 else { return nil }
            return CardGlow(intensity: min(spent, 1), isAlarm: spent >= 0.9)
        }
    }
}

/// The full-width advice banner: the advice, tinted by the advised provider, with that
/// provider's status as the detail line.
nonisolated struct AdviceBanner: Hashable, Sendable {
    let title: String
    let detail: String?
    /// Nil for advice about every provider (spent).
    let provider: Provider?

    init(advice: Advice, cards: [ProviderCard]) {
        title = advice.text
        provider = advice.provider
        guard let card = cards.first(where: { $0.provider == advice.provider }) else {
            detail = nil
            return
        }
        var parts = [card.statusLine.title.lowercased(), card.statusLine.detail]
        if let budget = card.budget { parts.append("resets in \(budget.resetIn)") }
        detail = parts.joined(separator: " · ")
    }
}

nonisolated extension Advice {
    /// The provider the advice is about; nil when it covers every provider.
    var provider: Provider? {
        switch self {
        case .keepUsing(let p), .useNext(let p), .useNow(let p), .fiveHourOut(let p, _), .rest(let p, _): p
        case .spent: nil
        }
    }
}

nonisolated extension ProviderCard {
    /// The headline in `mode`; `windowLabel` names the trailing window the tokens cover.
    func headline(_ mode: HeadlineMode, windowLabel: String) -> CardHeadline {
        if mode == .budget, let budget {
            return CardHeadline(mode: .budget, value: CockpitFormat.percent(budget.spent),
                                caption: "of \(budget.name) budget spent",
                                detail: "\(tokensText) tokens · resets in \(budget.resetIn)")
        }
        return CardHeadline(mode: .tokens, value: CockpitFormat.headlineTokens(tokens),
                            caption: "tokens · last \(windowLabel) · \(turns) turns · \(sessions) sessions", detail: nil)
    }

    /// Average burn over the trailing window, e.g. "432/min".
    func averageRateText(window: TimeInterval) -> String {
        CockpitFormat.rate(window > 0 ? Double(tokens) / (window / 60) : 0)
    }

    /// Spent: nothing left; over pace: the hourly share that still makes the reset; else the
    /// hourly share that lasts to it.
    static func spendAdvice(_ pace: Pace) -> String {
        if pace.percent >= AdviceEngine.weeklyFull { return "Nothing left until it resets" }
        let perHour = String(format: "%.1f%%", pace.allowancePerHour * 100)
        return pace.isOver
            ? "Slow to \(perHour) an hour to make it to the reset"
            : "Spend up to \(perHour) an hour and it lasts to the reset"
    }
}

nonisolated extension TokenSplit {
    /// Cache reads as a share of everything the model took in (input, cache write, cache
    /// read); nil when it took in nothing.
    var cacheReadShare: Double? {
        let takenIn = input + cacheWrite + cacheRead
        return takenIn > 0 ? Double(cacheRead) / Double(takenIn) : nil
    }
}

nonisolated extension CockpitFormat {
    /// Like `tokens`, but whole thousands from 100K: "999", "1.5K", "99.9K", "623K", "2.5M".
    static func headlineTokens(_ count: Int) -> String {
        guard count >= 100_000, count < 1_000_000 else { return tokens(count) }
        let thousands = Int((Double(count) / 1000).rounded())
        return thousands < 1000 ? "\(thousands)K" : tokens(count)
    }
}
