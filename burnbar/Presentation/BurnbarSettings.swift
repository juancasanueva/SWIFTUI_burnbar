//
//  BurnbarSettings.swift
//  burnbar
//

import Foundation
import Observation

/// The heat strip's trailing window.
nonisolated enum StripWindow: String, CaseIterable, Hashable, Sendable {
    case oneHour = "1h"
    case threeHours = "3h"
    case sixHours = "6h"
    case twelveHours = "12h"
    case oneDay = "1d"

    var duration: TimeInterval {
        switch self {
        case .oneHour: 3600
        case .threeHours: 3 * 3600
        case .sixHours: 6 * 3600
        case .twelveHours: 12 * 3600
        case .oneDay: 24 * 3600
        }
    }

    /// The collectors keep this much history so any window can be picked without a restart.
    static let longest = StripWindow.oneDay
}

/// Heat cells per strip lane.
nonisolated enum CellsPerLane: Int, CaseIterable, Hashable, Sendable {
    case eight = 8
    case twelve = 12
    case eighteen = 18
    case twentyFour = 24
}

/// How often transcripts are rescanned.
nonisolated enum RefreshInterval: Int, CaseIterable, Hashable, Sendable {
    case fiveSeconds = 5
    case tenSeconds = 10
    case thirtySeconds = 30
    case oneMinute = 60

    var duration: Duration { .seconds(rawValue) }
}

/// How often plan limits are fetched.
nonisolated enum LimitsRefreshInterval: Int, CaseIterable, Hashable, Sendable {
    case twoMinutes = 120
    case fiveMinutes = 300
    case tenMinutes = 600
    case thirtyMinutes = 1800

    var seconds: TimeInterval { TimeInterval(rawValue) }
}

nonisolated enum ThemePreference: String, CaseIterable, Hashable, Sendable {
    case dark, light, system
}

/// What a card's headline number shows.
nonisolated enum HeadlineMode: String, CaseIterable, Hashable, Sendable {
    case budget, tokens
}

/// When a card glows.
nonisolated enum GlowWhen: String, CaseIterable, Hashable, Sendable {
    case over, burning, spent, never
}

/// The user's preferences, persisted in `defaults` as they change and read back on launch.
/// Unknown or missing stored values fall back to the defaults.
@Observable
final class BurnbarSettings {
    nonisolated enum Key {
        static let enabledProviders = "settings.enabledProviders"
        static let showAccountNames = "settings.showAccountNames"
        static let readClaudeLimits = "settings.readClaudeLimits"
        static let stripWindow = "settings.stripWindow"
        static let cellsPerLane = "settings.cellsPerLane"
        static let refreshInterval = "settings.refreshInterval"
        static let limitsRefreshInterval = "settings.limitsRefreshInterval"
        static let suggestNextSub = "settings.suggestNextSub"
        static let showFiveHourWindows = "settings.showFiveHourWindows"
        static let theme = "settings.theme"
        static let headline = "settings.headline"
        static let glowWhen = "settings.glowWhen"
        static let emberMotion = "settings.emberMotion"
        static let launchAtLogin = "settings.launchAtLogin"
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Providers with a card, a strip lane and advice.
    var enabledProviders: Set<Provider> {
        didSet {
            let raw = Provider.allCases.filter(enabledProviders.contains).map(\.rawValue)
            defaults.set(raw, forKey: Key.enabledProviders)
        }
    }
    /// Cards name the signed-in account.
    var showAccountNames: Bool { didSet { defaults.set(showAccountNames, forKey: Key.showAccountNames) } }
    /// Claude's plan usage is fetched (Keychain and network); off, its card shows tokens only.
    var readClaudeLimits: Bool { didSet { defaults.set(readClaudeLimits, forKey: Key.readClaudeLimits) } }
    var stripWindow: StripWindow { didSet { defaults.set(stripWindow.rawValue, forKey: Key.stripWindow) } }
    var cellsPerLane: CellsPerLane { didSet { defaults.set(cellsPerLane.rawValue, forKey: Key.cellsPerLane) } }
    var refreshInterval: RefreshInterval { didSet { defaults.set(refreshInterval.rawValue, forKey: Key.refreshInterval) } }
    var limitsRefreshInterval: LimitsRefreshInterval {
        didSet { defaults.set(limitsRefreshInterval.rawValue, forKey: Key.limitsRefreshInterval) }
    }
    /// The advice may suggest which subscription to use; off, only warnings show.
    var suggestNextSub: Bool { didSet { defaults.set(suggestNextSub, forKey: Key.suggestNextSub) } }
    /// Cards list 5-hour session windows; off, only one about to run out.
    var showFiveHourWindows: Bool { didSet { defaults.set(showFiveHourWindows, forKey: Key.showFiveHourWindows) } }
    var theme: ThemePreference { didSet { defaults.set(theme.rawValue, forKey: Key.theme) } }
    var headline: HeadlineMode { didSet { defaults.set(headline.rawValue, forKey: Key.headline) } }
    var glowWhen: GlowWhen { didSet { defaults.set(glowWhen.rawValue, forKey: Key.glowWhen) } }
    var emberMotion: Bool { didSet { defaults.set(emberMotion, forKey: Key.emberMotion) } }
    /// The stored preference only; registering the login item is the Setup screen's job.
    var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: Key.launchAtLogin) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        enabledProviders = defaults.stringArray(forKey: Key.enabledProviders)
            .map { Set($0.compactMap(Provider.init(rawValue:))) } ?? Set(Provider.allCases)
        showAccountNames = Self.bool(defaults, Key.showAccountNames, default: true)
        readClaudeLimits = Self.bool(defaults, Key.readClaudeLimits, default: true)
        stripWindow = defaults.string(forKey: Key.stripWindow).flatMap(StripWindow.init(rawValue:)) ?? .sixHours
        cellsPerLane = Self.int(defaults, Key.cellsPerLane).flatMap(CellsPerLane.init(rawValue:)) ?? .twelve
        refreshInterval = Self.int(defaults, Key.refreshInterval).flatMap(RefreshInterval.init(rawValue:)) ?? .fiveSeconds
        limitsRefreshInterval = Self.int(defaults, Key.limitsRefreshInterval)
            .flatMap(LimitsRefreshInterval.init(rawValue:)) ?? .fiveMinutes
        suggestNextSub = Self.bool(defaults, Key.suggestNextSub, default: true)
        showFiveHourWindows = Self.bool(defaults, Key.showFiveHourWindows, default: false)
        theme = defaults.string(forKey: Key.theme).flatMap(ThemePreference.init(rawValue:)) ?? .dark
        headline = defaults.string(forKey: Key.headline).flatMap(HeadlineMode.init(rawValue:)) ?? .budget
        glowWhen = defaults.string(forKey: Key.glowWhen).flatMap(GlowWhen.init(rawValue:)) ?? .over
        emberMotion = Self.bool(defaults, Key.emberMotion, default: true)
        launchAtLogin = Self.bool(defaults, Key.launchAtLogin, default: false)
    }

    func isEnabled(_ provider: Provider) -> Bool { enabledProviders.contains(provider) }

    func setEnabled(_ provider: Provider, _ isOn: Bool) {
        if isOn { enabledProviders.insert(provider) } else { enabledProviders.remove(provider) }
    }

    /// Whether the store fetches `provider`'s limits: enabled, and for Claude only when allowed.
    func readsLimits(of provider: Provider) -> Bool {
        isEnabled(provider) && (provider != .claude || readClaudeLimits)
    }

    var grid: StripGrid { StripGrid(window: stripWindow.duration, cells: cellsPerLane.rawValue) }

    var cardOptions: CardOptions {
        CardOptions(showsAccountName: showAccountNames, showsFiveHourWindows: showFiveHourWindows)
    }

    /// Everything the store reacts to; observed so a change republishes at once.
    var storeInputs: StoreSettingsInputs {
        StoreSettingsInputs(enabledProviders: enabledProviders, readClaudeLimits: readClaudeLimits, grid: grid,
                            refreshInterval: refreshInterval, limitsRefreshInterval: limitsRefreshInterval,
                            suggestNextSub: suggestNextSub, cardOptions: cardOptions)
    }

    private static func bool(_ defaults: UserDefaults, _ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    private static func int(_ defaults: UserDefaults, _ key: String) -> Int? {
        defaults.object(forKey: key) as? Int
    }
}

/// The settings the usage store depends on, as one comparable value.
nonisolated struct StoreSettingsInputs: Hashable, Sendable {
    let enabledProviders: Set<Provider>
    let readClaudeLimits: Bool
    let grid: StripGrid
    let refreshInterval: RefreshInterval
    let limitsRefreshInterval: LimitsRefreshInterval
    let suggestNextSub: Bool
    let cardOptions: CardOptions
}
