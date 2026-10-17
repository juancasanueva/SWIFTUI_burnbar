//
//  CockpitTheme.swift
//  burnbar
//
//  Semantic colour tokens for the cockpit and the setup screen (dark matches the references,
//  light is its daytime variant), plus the small building blocks both screens share.
//

import SwiftUI

/// The cockpit's colour tokens for one colour scheme. Dark is the deep navy terminal look of
/// the references; light is its daytime variant.
struct CockpitPalette: Hashable {
    /// The panel behind everything.
    let panel: Color
    /// A card or a tinted box.
    let card: Color
    /// A flat setup row, a shade lighter than the panel.
    let row: Color
    /// The burndown plot area.
    let plot: Color
    /// 1 pt neutral box borders.
    let border: Color
    let primary: Color
    /// Muted lavender-grey captions.
    let secondary: Color
    let tertiary: Color
    /// Empty gauge and bar tracks.
    let track: Color
    /// The header's total and meta line.
    let accent: Color
    let good: Color
    let warn: Color
    let bad: Color
    let isDark: Bool

    static let dark = CockpitPalette(
        panel: Color(hex: 0x1A1B2C), card: Color(hex: 0x1D1E31), row: Color(hex: 0x24253A),
        plot: Color(hex: 0x1F2034), border: Color(hex: 0x33354F), primary: Color(hex: 0xD6D8EE),
        secondary: Color(hex: 0x8A8CA8), tertiary: Color(hex: 0x585A78), track: Color(hex: 0x2C2E46),
        accent: Color(hex: 0xFF7A45), good: Color(hex: 0x9ECE6A), warn: Color(hex: 0xE0AF68),
        bad: Color(hex: 0xF7768E), isDark: true
    )

    static let light = CockpitPalette(
        panel: Color(hex: 0xF3F3F8), card: Color(hex: 0xFFFFFF), row: Color(hex: 0xE9E9F1),
        plot: Color(hex: 0xF6F6FA), border: Color(hex: 0xD5D6E2), primary: Color(hex: 0x24253A),
        secondary: Color(hex: 0x6A6C86), tertiary: Color(hex: 0xA2A4BA), track: Color(hex: 0xE0E1EB),
        accent: Color(hex: 0xD2531C), good: Color(hex: 0x3F8F2A), warn: Color(hex: 0xB07216),
        bad: Color(hex: 0xD1335A), isDark: false
    )

    init(_ scheme: ColorScheme) { self = scheme == .light ? .light : .dark }

    private init(panel: Color, card: Color, row: Color, plot: Color, border: Color, primary: Color, secondary: Color,
                 tertiary: Color, track: Color, accent: Color, good: Color, warn: Color, bad: Color, isDark: Bool) {
        self.panel = panel
        self.card = card
        self.row = row
        self.plot = plot
        self.border = border
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.track = track
        self.accent = accent
        self.good = good
        self.warn = warn
        self.bad = bad
        self.isDark = isDark
    }

    /// A provider's lane colour: brighter on dark, the plain warm tone on light.
    func lane(_ provider: Provider) -> Color {
        let lane = LanePalette.lane(for: provider)
        return Color(isDark ? lane.accent : lane.warm)
    }

    func tone(_ tone: CardTone) -> Color {
        switch tone {
        case .good: good
        case .warn: warn
        case .bad: bad
        case .neutral: primary
        }
    }

    /// Pace badge colours: green, grey, amber, red.
    func verdict(_ verdict: Verdict) -> Color {
        switch verdict {
        case .onTrack: good
        case .atPace: secondary
        case .over: warn
        case .wayOver: bad
        }
    }
}

extension EnvironmentValues {
    @Entry var cockpitPalette = CockpitPalette.dark
}

extension Color {
    init(hex: UInt32) { self.init(RGBHex(hex)) }
}

extension ThemePreference {
    /// The scheme the panel forces; nil follows the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }

    /// The scheme the panel renders with: the forced one, or `system` when following it.
    func resolved(system: ColorScheme) -> ColorScheme { colorScheme ?? system }
}

extension HeadlineMode {
    var toggled: HeadlineMode { self == .budget ? .tokens : .budget }
}

/// The panel chrome shared by the cockpit and setup screens: monospaced type, the palette for
/// the current colour scheme and the panel background.
struct CockpitChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let palette = CockpitPalette(colorScheme)
        content
            .fontDesign(.monospaced)
            .foregroundStyle(palette.primary)
            .environment(\.cockpitPalette, palette)
            .background(palette.panel)
    }
}

extension GlowWhen {
    /// What lights a card up, in footer and setup wording, e.g. "over pace".
    var phrase: String {
        switch self {
        case .over: "over pace"
        case .burning: "burning now"
        case .spent: "budget spent"
        case .never: "no glow"
        }
    }
}

extension View {
    func cockpitChrome() -> some View { modifier(CockpitChrome()) }

    /// A card box: fill, a thin full border (`border`, else neutral) and, when glowing, a
    /// stronger tinted border, a faint tinted fill and a soft outer glow.
    func cockpitBox(border: Color? = nil, glow: Color? = nil, intensity: Double = 0) -> some View {
        modifier(CockpitBox(border: border, glow: glow, intensity: intensity))
    }
}

struct CockpitBox: ViewModifier {
    var border: Color? = nil
    let glow: Color?
    let intensity: Double

    @Environment(\.cockpitPalette) private var palette

    static let cornerRadius: CGFloat = 4

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        let edge = glow.map { $0.opacity(0.55 + 0.4 * intensity) } ?? border.map { $0.opacity(0.4) } ?? palette.border
        content
            .background {
                ZStack {
                    shape.fill(palette.card)
                    if let glow { shape.fill(glow.opacity(0.04 + 0.06 * intensity)) }
                }
                .shadow(color: (glow ?? .clear).opacity(0.55 + 0.35 * intensity), radius: 6 + 10 * intensity)
            }
            .overlay {
                shape.strokeBorder(edge, lineWidth: glow == nil ? 1 : 1.5)
            }
    }
}

/// A small uppercase, letter-spaced section label in muted grey, e.g. "BURN · TOKENS / MIN".
struct SectionLabel: View {
    let text: String
    var color: Color?

    @Environment(\.cockpitPalette) private var palette

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(color ?? palette.secondary)
            .lineLimit(1)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A value over a tiny uppercase label, e.g. "14K/min" / "NOW".
struct StatColumn: View {
    let label: String
    let value: String
    var color: Color?

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(color ?? palette.primary)
            Text(label.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .tracking(0.6)
                .foregroundStyle(palette.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// An uppercase, letter-spaced text button for the header, e.g. "SETUP" / "DONE".
struct CockpitTextButtonStyle: ButtonStyle {
    @Environment(\.cockpitPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(configuration.isPressed ? palette.secondary : palette.primary)
            .contentShape(Rectangle())
    }
}

/// A header icon button, e.g. refresh or quit; `isQuiet` draws it in muted grey.
struct CockpitIconButton: View {
    let systemImage: String
    let label: String
    var isQuiet = false
    let action: () -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isQuiet ? palette.tertiary : palette.primary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A thin flat gauge: a track, the used share in `color`, and an optional tick where an even
/// burn would be now.
struct UsageBar: View {
    let percent: Double
    let color: Color
    var tick: Double? = nil
    var height: CGFloat = 4

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1).fill(palette.track)
                RoundedRectangle(cornerRadius: 1).fill(color)
                    .frame(width: max(percent > 0 ? 4 : 0, width * min(max(percent, 0), 1)))
                if let tick {
                    Rectangle()
                        .fill(palette.primary.opacity(0.7))
                        .frame(width: 1.5, height: height + 6)
                        .offset(x: width * min(max(tick, 0), 1) - 0.75)
                }
            }
        }
        .frame(height: height)
    }
}
