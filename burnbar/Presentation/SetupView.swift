//
//  SetupView.swift
//  burnbar
//
//  The setup screen: a SETUP title row ("Back to the cockpit" on the right) over three columns
//  of uppercase group labels and flat rows (checkboxes, radios and capsule choices), then the
//  footer. Presentational: plain values and bindings in, closures out.
//

import SwiftUI

/// The bindings the setup screen edits. `PanelView` builds them from the settings.
struct SetupControls {
    var showAccountNames: Binding<Bool>
    var readClaudeLimits: Binding<Bool>
    var stripWindow: Binding<StripWindow>
    var cellsPerLane: Binding<CellsPerLane>
    var refreshInterval: Binding<RefreshInterval>
    var limitsRefreshInterval: Binding<LimitsRefreshInterval>
    var emberMotion: Binding<Bool>
    var suggestNextSub: Binding<Bool>
    var theme: Binding<ThemePreference>
    var headline: Binding<HeadlineMode>
    var glowWhen: Binding<GlowWhen>
    var showFiveHourWindows: Binding<Bool>
    /// Reads the setting; writing goes through the login item and may be reverted.
    var launchAtLogin: Binding<Bool>
    /// Reads and writes the updater, which persists the preference.
    var automaticUpdateChecks: Binding<Bool>
}

extension SetupControls {
    init(settings: BurnbarSettings, launchAtLogin: LaunchAtLoginController, updater: any AppUpdating) {
        @Bindable var settings = settings
        self.init(
            showAccountNames: $settings.showAccountNames,
            readClaudeLimits: $settings.readClaudeLimits,
            stripWindow: $settings.stripWindow,
            cellsPerLane: $settings.cellsPerLane,
            refreshInterval: $settings.refreshInterval,
            limitsRefreshInterval: $settings.limitsRefreshInterval,
            emberMotion: $settings.emberMotion,
            suggestNextSub: $settings.suggestNextSub,
            theme: $settings.theme,
            headline: $settings.headline,
            glowWhen: $settings.glowWhen,
            showFiveHourWindows: $settings.showFiveHourWindows,
            launchAtLogin: Binding(get: { settings.launchAtLogin }, set: { launchAtLogin.setEnabled($0) }),
            automaticUpdateChecks: Binding(get: { updater.automaticallyChecksForUpdates },
                                           set: { updater.automaticallyChecksForUpdates = $0 })
        )
    }
}

struct SetupView: View {
    let header: CockpitHeader
    let subscriptions: [SubscriptionRow]
    let warningsCaption: String
    let canWarnAgain: Bool
    /// Why launch at login is not what was asked for; nil when all is well.
    let loginItemMessage: String?
    let controls: SetupControls
    let updates: SetupUpdates
    let isRefreshing: Bool
    let onSetEnabled: (Provider, Bool) -> Void
    let onWarnMeAgain: () -> Void
    let onRefresh: () -> Void
    let onCheckForUpdates: () -> Void
    let onDone: () -> Void
    let onQuit: () -> Void

    static let columnWidth: CGFloat = 320
    static let columnSpacing: CGFloat = 24
    static let width = 3 * columnWidth + 2 * columnSpacing + 2 * CockpitView.padding

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SetupTitleRow(isRefreshing: isRefreshing, onDone: onDone, onRefresh: onRefresh, onQuit: onQuit)
            columns
            CockpitFooter(updatedAt: header.updatedAt)
        }
        .padding(CockpitView.padding)
        .frame(width: Self.width)
        .cockpitChrome()
    }

    static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    /// The three columns on their own (also rendered directly by the render test).
    var columns: some View {
        HStack(alignment: .top, spacing: Self.columnSpacing) {
            VStack(alignment: .leading, spacing: 18) {
                SubscriptionsGroup(subscriptions: subscriptions, showAccountNames: controls.showAccountNames,
                                   onSetEnabled: onSetEnabled)
                SetupGroup("Claude limits") {
                    CheckboxRow(title: "Read plan usage", caption: "asks for /usage", isOn: controls.readClaudeLimits)
                    SetupNote("Uses Claude Code's sign-in from the login keychain to ask api.anthropic.com for your plan usage, as /usage does. Never stored, never refreshed.")
                }
                SetupGroup("Warnings") {
                    WarnMeAgainRow(caption: warningsCaption, isEnabled: canWarnAgain, action: onWarnMeAgain)
                }
                SetupGroup("The panel") {
                    CapsuleChoices(title: "Theme", selection: controls.theme)
                    CheckboxRow(title: "Launch at login", caption: loginItemMessage ?? "with your Mac",
                                isOn: controls.launchAtLogin, captionIsAlert: loginItemMessage != nil)
                }
            }
            .frame(width: Self.columnWidth, alignment: .leading)
            VStack(alignment: .leading, spacing: 18) {
                SetupGroup("Card headline") {
                    RadioRows(title: "Card headline", selection: controls.headline, caption: \.setupCaption)
                }
                SetupGroup("Card glow · what lights a card up") {
                    RadioRows(title: "Card glow", selection: controls.glowWhen, caption: \.setupCaption,
                              name: { SetupView.capitalizedFirst($0.phrase) })
                }
                SetupGroup("Budget windows") {
                    CheckboxRow(title: "5-hour session windows",
                                caption: SetupDisplay.fiveHourCaption(isOn: controls.showFiveHourWindows.wrappedValue),
                                isOn: controls.showFiveHourWindows)
                }
            }
            .frame(width: Self.columnWidth, alignment: .leading)
            StripGroup(controls: controls, updates: updates, onCheckForUpdates: onCheckForUpdates)
                .frame(width: Self.columnWidth, alignment: .leading)
        }
    }
}

// MARK: Groups

/// "SETUP  everything Burnbar can show, and how" with "Back to the cockpit" (Esc), refresh and
/// a quiet quit on the right.
private struct SetupTitleRow: View {
    let isRefreshing: Bool
    let onDone: () -> Void
    let onRefresh: () -> Void
    let onQuit: () -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text("SETUP")
                .font(.system(size: 17, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .accessibilityAddTraits(.isHeader)
            Text("everything Burnbar can show, and how")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(palette.secondary)
            Spacer(minLength: 8)
            Button("Back to the cockpit", action: onDone)
                .buttonStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .keyboardShortcut(.cancelAction)
                .accessibilityHint("Returns to the cockpit")
            CockpitIconButton(systemImage: "arrow.clockwise",
                              label: isRefreshing ? "Refreshing limits" : "Refresh limits", action: onRefresh)
                .disabled(isRefreshing)
            CockpitIconButton(systemImage: "power", label: "Quit Burnbar", isQuiet: true, action: onQuit)
                .keyboardShortcut("q")
        }
    }
}

private struct SubscriptionsGroup: View {
    let subscriptions: [SubscriptionRow]
    let showAccountNames: Binding<Bool>
    let onSetEnabled: (Provider, Bool) -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        SetupGroup("Subscriptions · tick any") {
            ForEach(subscriptions) { row in
                CheckboxRow(title: row.name, caption: row.caption.lowercased(),
                            isOn: Binding(get: { row.isEnabled }, set: { onSetEnabled(row.provider, $0) }),
                            titleColor: palette.lane(row.provider), captionColor: captionColor(row))
            }
            CheckboxRow(title: "Account names", caption: "off to screen share", isOn: showAccountNames)
            SetupNote("A ticked subscription gets a card in the cockpit and a lane on the bar. Unticked, it has neither.")
        }
    }

    private func captionColor(_ row: SubscriptionRow) -> Color {
        switch row.tone {
        case .normal: palette.lane(row.provider)
        case .alert: palette.bad
        case .muted: palette.tertiary
        }
    }
}

private struct StripGroup: View {
    let controls: SetupControls
    let updates: SetupUpdates
    let onCheckForUpdates: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SetupGroup("The strip on the bar") {
                CheckboxRow(title: "Ember motion", caption: "live cells breathe", isOn: controls.emberMotion)
                CheckboxRow(title: "Suggest a sub", caption: "when nothing is over", isOn: controls.suggestNextSub)
            }
            SetupGroup("History window") {
                CapsuleChoices(title: "History window", selection: controls.stripWindow)
            }
            SetupGroup("Cells per lane") {
                CapsuleChoices(title: "Cells per lane", selection: controls.cellsPerLane)
            }
            SetupGroup("Rescan transcripts every") {
                CapsuleChoices(title: "Refresh", selection: controls.refreshInterval)
            }
            SetupGroup("Ask for plan figures every") {
                CapsuleChoices(title: "Limits refresh", selection: controls.limitsRefreshInterval)
            }
            UpdatesGroup(updates: updates, automaticChecks: controls.automaticUpdateChecks,
                         onCheck: onCheckForUpdates)
            AboutNote()
        }
    }
}

/// "Check for Updates…", the automatic-checks preference, then the version and when it last looked.
private struct UpdatesGroup: View {
    let updates: SetupUpdates
    let automaticChecks: Binding<Bool>
    let onCheck: () -> Void

    var body: some View {
        SetupGroup("Updates") {
            CheckForUpdatesRow(isEnabled: updates.canCheck, action: onCheck)
            CheckboxRow(title: "Automatic checks", caption: "off until you ask", isOn: automaticChecks)
            SetupNote("\(updates.versionLine) · \(updates.lastChecked)")
        }
    }
}

/// "Check for Updates…" as a flat row; disabled while a check is already running.
private struct CheckForUpdatesRow: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SetupRowLayout(glyph: "arrow.down.circle", title: "Check for Updates…", isActive: false)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityLabel("Check for Updates")
        .accessibilityHint("Looks for a newer Burnbar now")
    }
}

private struct AboutNote: View {
    @Environment(\.cockpitPalette) private var palette
    @Environment(\.openURL) private var openURL

    private static let repository = URL(string: "https://github.com/nixfred/burnbar")!

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SetupNote("Burnbar is a macOS port of Burn Bar, the Omarchy bar plugin by nixfred. MIT licence.")
            // A plain button, not `Link`: drawn in SwiftUI, so it also shows in rendered snapshots.
            Button { openURL(Self.repository) } label: {
                Text("github.com/nixfred/burnbar")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(palette.secondary)
                    .underline()
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isLink)
            .accessibilityHint("Opens nixfred's Burn Bar repository in your browser")
        }
    }
}

// MARK: Building blocks

/// An uppercase, letter-spaced group label over its rows.
struct SetupGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title)
                .padding(.bottom, 2)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A flat row: a glyph, a title and a muted right-aligned caption. Filled when `isActive`.
private struct SetupRowLayout: View {
    let glyph: String
    let title: String
    var caption: String?
    var isActive: Bool
    var titleColor: Color?
    var captionColor: Color?

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: glyph)
                .font(.system(size: 12))
                .foregroundStyle(isActive ? palette.primary : palette.tertiary)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(titleColor ?? palette.primary)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer(minLength: 8)
            if let caption {
                Text(caption)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(captionColor ?? palette.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .truncationMode(.tail)
                    .help(caption)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 34)
        .background(RoundedRectangle(cornerRadius: 4).fill(isActive ? palette.row : Color.clear))
        .contentShape(Rectangle())
    }
}

/// A boolean as a checkbox row; a real `Toggle`, so VoiceOver reads it as a switch.
struct CheckboxRow: View {
    let title: String
    var caption: String?
    let isOn: Binding<Bool>
    var titleColor: Color?
    var captionColor: Color?
    var captionIsAlert = false

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        Toggle(title, isOn: isOn)
            .toggleStyle(CheckboxGlyphStyle(title: title, caption: caption, titleColor: titleColor,
                                            captionColor: captionIsAlert ? palette.bad : captionColor))
            .accessibilityLabel(title)
            .accessibilityHint(caption ?? "")
    }
}

private struct CheckboxGlyphStyle: ToggleStyle {
    let title: String
    let caption: String?
    let titleColor: Color?
    let captionColor: Color?

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            SetupRowLayout(glyph: configuration.isOn ? "checkmark.square.fill" : "square", title: title,
                           caption: caption, isActive: configuration.isOn, titleColor: titleColor,
                           captionColor: captionColor)
        }
        .buttonStyle(.plain)
    }
}

/// A single choice as one radio row per option, each with its own muted caption.
struct RadioRows<Option: SetupOption>: View {
    let title: String
    let selection: Binding<Option>
    let caption: (Option) -> String?
    let name: (Option) -> String

    init(title: String, selection: Binding<Option>, caption: @escaping (Option) -> String?,
         name: @escaping (Option) -> String = \.label) {
        self.title = title
        self.selection = selection
        self.caption = caption
        self.name = name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(Option.allCases)) { option in
                let isSelected = option == selection.wrappedValue
                Button { selection.wrappedValue = option } label: {
                    SetupRowLayout(glyph: isSelected ? "largecircle.fill.circle" : "circle", title: name(option),
                                   caption: caption(option), isActive: isSelected)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(name(option))
                .accessibilityHint(caption(option) ?? "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// Short choices as outlined capsules, equal widths; the selected one filled.
struct CapsuleChoices<Option: SetupOption>: View {
    let title: String
    let selection: Binding<Option>

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(Option.allCases)) { option in
                let isSelected = option == selection.wrappedValue
                Button { selection.wrappedValue = option } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
                        .foregroundStyle(isSelected ? palette.primary : palette.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(isSelected ? palette.row.opacity(1) : Color.clear))
                        .overlay(Capsule().strokeBorder(isSelected ? palette.secondary : palette.border, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// "Warn me again" as a flat row with a reset glyph, with how many warnings are dismissed.
private struct WarnMeAgainRow: View {
    let caption: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SetupRowLayout(glyph: "arrow.counterclockwise", title: "Warn me again", caption: caption, isActive: false)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityLabel("Warn me again")
        .accessibilityValue(caption)
        .accessibilityHint("Shows dismissed advice again")
    }
}

/// A muted explanatory paragraph under a group.
private struct SetupNote: View {
    let text: String

    @Environment(\.cockpitPalette) private var palette

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }
}

private extension HeadlineMode {
    var setupCaption: String? {
        switch self {
        case .budget: "spent, and will it last"
        case .tokens: "raw burn in the window"
        }
    }
}

private extension GlowWhen {
    var setupCaption: String? {
        switch self {
        case .over: "faster than the plan"
        case .burning: "burn in the last 5 min"
        case .spent: "brighter as it fills"
        case .never: nil
        }
    }
}

#if DEBUG
extension SetupControls {
    /// Constant bindings with the default settings, for previews and render tests.
    static var preview: SetupControls {
        SetupControls(showAccountNames: .constant(false), readClaudeLimits: .constant(true),
                      stripWindow: .constant(.oneDay), cellsPerLane: .constant(.twelve),
                      refreshInterval: .constant(.fiveSeconds), limitsRefreshInterval: .constant(.fiveMinutes),
                      emberMotion: .constant(true), suggestNextSub: .constant(true), theme: .constant(.dark),
                      headline: .constant(.tokens), glowWhen: .constant(.over), showFiveHourWindows: .constant(true),
                      launchAtLogin: .constant(true), automaticUpdateChecks: .constant(false))
    }
}

extension SetupView {
    /// The fixture setup screen.
    static var preview: SetupView {
        SetupView(header: CockpitPreview.header,
                  subscriptions: SubscriptionRow.rows(cards: CockpitPreview.cards, enabled: Set(Provider.allCases)),
                  warningsCaption: SetupDisplay.warningsCaption(dismissedCount: 0), canWarnAgain: false,
                  loginItemMessage: nil, controls: .preview,
                  updates: SetupUpdates(versionLine: "Burnbar 1.0 (1)", canCheck: true, lastChecked: "Never checked"),
                  isRefreshing: false, onSetEnabled: { _, _ in }, onWarnMeAgain: {}, onRefresh: {},
                  onCheckForUpdates: {}, onDone: {}, onQuit: {})
    }
}

#Preview("Setup") {
    SetupView.preview
}

#Preview("Setup, light") {
    SetupView.preview
        .preferredColorScheme(.light)
}
#endif
