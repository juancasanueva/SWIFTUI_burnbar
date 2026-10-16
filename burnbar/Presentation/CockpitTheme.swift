//
//  CockpitTheme.swift
//  burnbar
//
//  Semantic colour tokens for the cockpit and the setup screen (dark matches the references,
//  light is its daytime variant), plus the small building blocks both screens share.
//

import SwiftUI

/// The cockpit's colour tokens for one colour scheme.
struct CockpitPalette: Hashable {
    /// The panel behind everything.
    let panel: Color
    /// A card or a tinted box.
    let card: Color
    /// The burndown plot area.
    let plot: Color
    /// 1 pt card and box borders.
    let border: Color
    let primary: Color
    let secondary: Color
    let tertiary: Color
    /// Empty gauge and bar tracks.
    let track: Color
    let good: Color
    let warn: Color
    let bad: Color
    let isDark: Bool

    static let dark = CockpitPalette(
        panel: Color(hex: 0x1C1C1E), card: Color(hex: 0x26262A), plot: Color(hex: 0x1F1F22),
        border: Color(hex: 0x38383D), primary: Color(hex: 0xECECEE), secondary: Color(hex: 0x9C9CA3),
        tertiary: Color(hex: 0x5F5F66), track: Color(hex: 0x3A3A40), good: Color(hex: 0x5BD16A),
        warn: Color(hex: 0xFFB547), bad: Color(hex: 0xFF5F57), isDark: true
    )

    static let light = CockpitPalette(
        panel: Color(hex: 0xF2F2F4), card: Color(hex: 0xFFFFFF), plot: Color(hex: 0xF5F5F7),
        border: Color(hex: 0xD9D9DE), primary: Color(hex: 0x1C1C1E), secondary: Color(hex: 0x6C6C72),
        tertiary: Color(hex: 0xA3A3AA), track: Color(hex: 0xE3E3E8), good: Color(hex: 0x1F9D47),
        warn: Color(hex: 0xC77800), bad: Color(hex: 0xD93B30), isDark: false
    )

    init(_ scheme: ColorScheme) { self = scheme == .light ? .light : .dark }

    private init(panel: Color, card: Color, plot: Color, border: Color, primary: Color, secondary: Color,
                 tertiary: Color, track: Color, good: Color, warn: Color, bad: Color, isDark: Bool) {
        self.panel = panel
        self.card = card
        self.plot = plot
        self.border = border
        self.primary = primary
        self.secondary = secondary
        self.tertiary = tertiary
        self.track = track
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

extension View {
    func cockpitChrome() -> some View { modifier(CockpitChrome()) }

    /// A card box: fill, 1 pt border (brighter when glowing) and an optional outer glow.
    func cockpitBox(glow: Color? = nil, intensity: Double = 0) -> some View {
        modifier(CockpitBox(glow: glow, intensity: intensity))
    }
}

struct CockpitBox: ViewModifier {
    let glow: Color?
    let intensity: Double

    @Environment(\.cockpitPalette) private var palette

    static let cornerRadius: CGFloat = 10

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius)
        content
            .background {
                shape.fill(palette.card)
                    .shadow(color: (glow ?? .clear).opacity(0.75 * intensity), radius: 4 + 10 * intensity)
            }
            .overlay {
                shape.strokeBorder(glow.map { $0.opacity(0.45 + 0.45 * intensity) } ?? palette.border, lineWidth: 1)
            }
    }
}

/// A small uppercase section label in secondary grey, e.g. "WINDOWS".
struct SectionLabel: View {
    let text: String

    @Environment(\.cockpitPalette) private var palette

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(1)
            .foregroundStyle(palette.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A tiny uppercase label over a bold value, e.g. "NOW" / "14K/min".
struct StatColumn: View {
    let label: String
    let value: String

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(palette.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// An uppercase text button for the header, e.g. "SETUP" / "DONE".
struct CockpitTextButtonStyle: ButtonStyle {
    @Environment(\.cockpitPalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(configuration.isPressed ? palette.secondary : palette.primary)
            .contentShape(Rectangle())
    }
}

/// A header icon button, e.g. refresh or quit.
struct CockpitIconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.primary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A thin gauge: a track, the used share in `color`, and an optional tick where an even burn
/// would be now.
struct UsageBar: View {
    let percent: Double
    let color: Color
    var tick: Double? = nil

    @Environment(\.cockpitPalette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(palette.track)
                Capsule().fill(color).frame(width: max(percent > 0 ? 6 : 0, width * min(max(percent, 0), 1)))
                if let tick {
                    Rectangle()
                        .fill(palette.secondary)
                        .frame(width: 1.5, height: 10)
                        .offset(x: width * min(max(tick, 0), 1) - 0.75)
                }
            }
        }
        .frame(height: 6)
    }
}
