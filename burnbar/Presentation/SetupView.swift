//
//  SetupView.swift
//  burnbar
//
//  The setup screen: the cockpit's header (DONE instead of SETUP) over three columns of boxes
//  (subscriptions, Claude limits and warnings; the strip; cards and about), then the footer.
//  Presentational: plain values and bindings in, closures out.
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
}

extension SetupControls {
    init(settings: BurnbarSettings, launchAtLogin: LaunchAtLoginController) {
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
            launchAtLogin: Binding(get: { settings.launchAtLogin }, set: { launchAtLogin.setEnabled($0) })
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
    let isRefreshing: Bool
    let onSetEnabled: (Provider, Bool) -> Void
    let onWarnMeAgain: () -> Void
    let onRefresh: () -> Void
    let onDone: () -> Void
    let onQuit: () -> Void

    static let columnWidth: CGFloat = 290
    static let width = 3 * columnWidth + 2 * CockpitView.spacing + 2 * CockpitView.padding

    var body: some View {
        VStack(alignment: .leading, spacing: CockpitView.spacing) {
            CockpitHeaderView(header: header, isSetupOpen: true, isRefreshing: isRefreshing,
                              onToggleSetup: onDone, onRefresh: onRefresh, onQuit: onQuit)
            columns
            CockpitFooter(updatedAt: header.updatedAt)
        }
        .padding(CockpitView.padding)
        .frame(width: Self.width)
        .cockpitChrome()
    }

    /// The three columns on their own (also rendered directly by the render test).
    var columns: some View {
        HStack(alignment: .top, spacing: CockpitView.spacing) {
            VStack(spacing: CockpitView.spacing) {
                SubscriptionsBox(subscriptions: subscriptions, showAccountNames: controls.showAccountNames,
                                 onSetEnabled: onSetEnabled)
                SetupBox("Claude limits", systemImage: "gauge.with.dots.needle.33percent") {
                    SetupToggleRow(title: "Read plan usage",
                                   caption: "Uses Claude Code's sign-in from the login keychain to ask api.anthropic.com for your plan usage, as /usage does. Never stored, never refreshed.",
                                   isOn: controls.readClaudeLimits)
                }
                SetupBox("Warnings", systemImage: "exclamationmark.triangle") {
                    WarnMeAgainRow(caption: warningsCaption, isEnabled: canWarnAgain, action: onWarnMeAgain)
                }
            }
            .frame(width: Self.columnWidth)
            StripBox(controls: controls)
                .frame(width: Self.columnWidth)
            VStack(spacing: CockpitView.spacing) {
                CardsBox(controls: controls, loginItemMessage: loginItemMessage)
                AboutBox()
            }
            .frame(width: Self.columnWidth)
        }
        .fontDesign(.default)
    }
}

// MARK: Boxes

private struct SubscriptionsBox: View {
    let subscriptions: [SubscriptionRow]
    let showAccountNames: Binding<Bool>
    let onSetEnabled: (Provider, Bool) -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        SetupBox("Subscriptions", systemImage: "flame") {
            ForEach(subscriptions) { row in
                SetupToggleRow(title: row.name, caption: row.caption,
                               isOn: Binding(get: { row.isEnabled }, set: { onSetEnabled(row.provider, $0) }),
                               tint: palette.lane(row.provider), dot: palette.lane(row.provider))
            }
            SetupToggleRow(title: "Account names",
                           caption: "Each card names the login it reads. Turn off for a screen share.",
                           isOn: showAccountNames)
        }
    }
}

private struct StripBox: View {
    let controls: SetupControls

    var body: some View {
        SetupBox("Strip", systemImage: "chart.bar.fill") {
            SetupPillRow(title: "Window", caption: "How far back the strip reaches.", selection: controls.stripWindow)
            SetupPillRow(title: "Cells per lane", selection: controls.cellsPerLane)
            SetupPillRow(title: "Refresh", caption: "Rescans the transcripts.", selection: controls.refreshInterval)
            SetupPillRow(title: "Limits refresh", caption: "Asks the providers for fresh plan figures.",
                         selection: controls.limitsRefreshInterval)
            SetupToggleRow(title: "Ember motion",
                           caption: "Cells flicker and glow, a lane flashes when new burn lands. Off with Reduce Motion.",
                           isOn: controls.emberMotion)
            SetupToggleRow(title: "Suggest the next sub",
                           caption: "With nothing to warn about, the chip names the subscription to use next.",
                           isOn: controls.suggestNextSub)
        }
    }
}

private struct CardsBox: View {
    let controls: SetupControls
    let loginItemMessage: String?

    var body: some View {
        SetupBox("Cards", systemImage: "rectangle.split.2x1") {
            SetupPillRow(title: "Theme", selection: controls.theme)
            SetupPillRow(title: "Headline", caption: "What each card leads with.", selection: controls.headline)
            SetupPillRow(title: "Glow when", caption: "A card lights up for one reason.", selection: controls.glowWhen)
            SetupToggleRow(title: "5-hour session windows", caption: "Shown anyway when one is about to run out.",
                           isOn: controls.showFiveHourWindows)
            SetupToggleRow(title: "Launch at login", caption: loginItemMessage, isOn: controls.launchAtLogin,
                           captionIsAlert: loginItemMessage != nil)
        }
    }
}

private struct AboutBox: View {
    @Environment(\.cockpitPalette) private var palette

    private static let repository = URL(string: "https://github.com/nixfred/burnbar")!

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("🔥 Burn Bar")
                    .font(.system(size: 14, weight: .bold))
                Text("MIT")
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(palette.track))
                    .accessibilityLabel("MIT licence")
            }
            .accessibilityElement(children: .combine)
            Text("A macOS port of Burn Bar, the Omarchy bar plugin by nixfred.")
                .font(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: Self.repository) {
                Label("github.com/nixfred/burnbar", systemImage: "arrow.up.right.square")
                    .font(.system(size: 11))
            }
            .foregroundStyle(.blue)
            .accessibilityHint("Opens the Burn Bar repository in your browser")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitBox()
    }
}

// MARK: Building blocks

/// A rounded box with an icon and an uppercase label over rows split by thin dividers.
struct SetupBox<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    @Environment(\.cockpitPalette) private var palette

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .accessibilityHidden(true)
                SectionLabel(title)
            }
            .padding(.bottom, 4)
            Group(subviews: content) { rows in
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        Rectangle().fill(palette.border).frame(height: 1)
                    }
                    row.padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cockpitBox()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// A title, an optional caption and a small switch on the right.
struct SetupToggleRow: View {
    let title: String
    var caption: String?
    let isOn: Binding<Bool>
    var tint: Color = .blue
    /// A lane-coloured dot before the title.
    var dot: Color?
    var captionIsAlert = false

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let dot {
                Circle().fill(dot).frame(width: 8, height: 8).padding(.top, 5)
            }
            SetupRowText(title: title, caption: caption, captionColor: captionIsAlert ? palette.bad : palette.secondary)
                .accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(tint)
                .accessibilityLabel(title)
                .accessibilityHint(caption ?? "")
        }
    }
}

/// A title, a row of pills and an optional caption.
struct SetupPillRow<Option: SetupOption>: View {
    let title: String
    var caption: String?
    let selection: Binding<Option>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            SegmentedPills(title: title, selection: selection)
            if let caption {
                SetupCaption(text: caption)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// One pill per option, equal widths; the selected one amber with dark text.
struct SegmentedPills<Option: SetupOption>: View {
    let title: String
    let selection: Binding<Option>

    @Environment(\.cockpitPalette) private var palette

    static var selectedFill: Color { Color(hex: 0xFDB338) }
    static var selectedText: Color { Color(hex: 0x1C1C1E) }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(Option.allCases)) { option in
                let isSelected = option == selection.wrappedValue
                Button { selection.wrappedValue = option } label: {
                    Text(option.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? Self.selectedText : palette.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? Self.selectedFill : palette.track))
                        .contentShape(RoundedRectangle(cornerRadius: 5))
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

/// "Warn me again" as a pill button, with how many warnings are dismissed.
private struct WarnMeAgainRow: View {
    let caption: String
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        HStack(spacing: 10) {
            Button(action: action) {
                Text("Warn me again")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(palette.track))
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .opacity(isEnabled ? 1 : 0.45)
            .accessibilityValue(caption)
            .accessibilityHint("Shows dismissed advice again")
            SetupCaption(text: caption)
                .accessibilityHidden(true)
        }
    }
}

private struct SetupRowText: View {
    let title: String
    let caption: String?
    let captionColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            if let caption {
                SetupCaption(text: caption, color: captionColor)
            }
        }
    }
}

private struct SetupCaption: View {
    let text: String
    var color: Color?

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(color ?? palette.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
                      launchAtLogin: .constant(true))
    }
}

extension SetupView {
    /// The fixture setup screen.
    static var preview: SetupView {
        SetupView(header: CockpitPreview.header,
                  subscriptions: SubscriptionRow.rows(cards: CockpitPreview.cards, enabled: Set(Provider.allCases)),
                  warningsCaption: SetupDisplay.warningsCaption(dismissedCount: 0), canWarnAgain: false,
                  loginItemMessage: nil, controls: .preview, isRefreshing: false,
                  onSetEnabled: { _, _ in }, onWarnMeAgain: {}, onRefresh: {}, onDone: {}, onQuit: {})
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
