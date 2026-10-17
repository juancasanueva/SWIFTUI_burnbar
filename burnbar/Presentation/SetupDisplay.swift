//
//  SetupDisplay.swift
//  burnbar
//
//  Pure decisions for the setup screen: subscription rows and their status captions, the
//  warnings caption, option labels, and launch at login kept in step with the login item.
//

import Foundation
import Observation

/// One subscription in SUBSCRIPTIONS: its name, what its card says right now, and its toggle.
nonisolated struct SubscriptionRow: Hashable, Sendable, Identifiable {
    let provider: Provider
    let name: String
    /// E.g. "Banked 51%", "On pace", "Spent until it resets", "Turned off".
    let caption: String
    let isEnabled: Bool

    var id: Provider { provider }

    /// One row per provider, in `Provider.allCases` order; `cards` covers the enabled ones.
    static func rows(cards: [ProviderCard], enabled: Set<Provider>) -> [SubscriptionRow] {
        Provider.allCases.map { provider in
            let isEnabled = enabled.contains(provider)
            return SubscriptionRow(provider: provider, name: provider.title,
                                   caption: caption(card: cards.first { $0.provider == provider }, isEnabled: isEnabled),
                                   isEnabled: isEnabled)
        }
    }

    /// The card's status line in sentence case; a spent budget reads "Spent until it resets".
    static func caption(card: ProviderCard?, isEnabled: Bool) -> String {
        guard isEnabled else { return "Turned off" }
        guard let card else { return "No plan reading" }
        if let spent = card.budget?.spent, spent >= AdviceEngine.weeklyFull { return "Spent until it resets" }
        let title = card.statusLine.title
        guard let first = title.first else { return title }
        return first.uppercased() + title.dropFirst().lowercased()
    }
}

nonisolated enum SetupDisplay {
    static func warningsCaption(dismissedCount: Int) -> String {
        dismissedCount > 0 ? "\(dismissedCount) dismissed" : "nothing dismissed"
    }
}

/// A short label for a pill in a segmented row.
nonisolated protocol SetupOption: Hashable, CaseIterable, Identifiable where AllCases: RandomAccessCollection {
    var label: String { get }
}

nonisolated extension SetupOption {
    var id: Self { self }
}

nonisolated extension StripWindow: SetupOption {
    var label: String { rawValue }
}

nonisolated extension CellsPerLane: SetupOption {
    var label: String { "\(rawValue)" }
}

nonisolated extension RefreshInterval: SetupOption {
    var label: String { "\(rawValue)s" }
}

nonisolated extension LimitsRefreshInterval: SetupOption {
    var label: String { "\(rawValue / 60)m" }
}

nonisolated extension ThemePreference: SetupOption {
    var label: String { rawValue.capitalized }
}

nonisolated extension HeadlineMode: SetupOption {
    var label: String { rawValue.capitalized }
}

nonisolated extension GlowWhen: SetupOption {
    var label: String { rawValue.capitalized }
}

/// Keeps `settings.launchAtLogin` in step with the real login item: `sync()` reads it, and
/// `setEnabled(_:)` changes it, reverting the toggle and saying why when that fails.
@Observable
final class LaunchAtLoginController {
    @ObservationIgnored private let item: any LoginItemControlling
    @ObservationIgnored private let settings: BurnbarSettings
    /// Why the toggle is not what was asked for; nil when all is well.
    private(set) var message: String?

    init(item: any LoginItemControlling, settings: BurnbarSettings) {
        self.item = item
        self.settings = settings
    }

    /// Reflects the login item's real state into the setting.
    func sync() {
        apply(item.status)
    }

    func setEnabled(_ isEnabled: Bool) {
        do {
            try item.setEnabled(isEnabled)
            apply(item.status)
        } catch {
            apply(item.status)
            message = "Couldn't change login item: \(error.localizedDescription)"
        }
    }

    /// Mirrors `status` into the setting; the message is the approval hint or nothing.
    private func apply(_ status: LoginItemStatus) {
        let isEnabled = status == .enabled
        if settings.launchAtLogin != isEnabled { settings.launchAtLogin = isEnabled }
        message = status == .requiresApproval ? "Allow Burnbar in System Settings › General › Login Items." : nil
    }
}
