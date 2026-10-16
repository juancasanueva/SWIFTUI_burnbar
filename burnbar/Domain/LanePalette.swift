//
//  LanePalette.swift
//  burnbar
//

/// A plain 24-bit RGB colour so the domain stays free of SwiftUI.
nonisolated struct RGBHex: Hashable, Sendable {
    let value: UInt32

    init(_ value: UInt32) { self.value = value & 0xFFFFFF }

    var red: Double { Double((value >> 16) & 0xFF) / 255 }
    var green: Double { Double((value >> 8) & 0xFF) / 255 }
    var blue: Double { Double(value & 0xFF) / 255 }
}

/// Heat ramp of one provider lane.
nonisolated struct Lane: Hashable, Sendable {
    let cold: RGBHex
    let warm: RGBHex
    let hot: RGBHex
}

/// Upstream burnbar colours.
nonisolated enum LanePalette {
    static let claude = Lane(cold: RGBHex(0x4A2113), warm: RGBHex(0xC4542A), hot: RGBHex(0xFF8A4B))
    static let codex = Lane(cold: RGBHex(0x0C3E33), warm: RGBHex(0x12977A), hot: RGBHex(0x2BE8B0))
    static let amber = RGBHex(0xFFC46B)
    static let whiteHot = RGBHex(0xFFF6EC)
    static let error = RGBHex(0xFF3B30)

    static func lane(for provider: Provider) -> Lane {
        switch provider {
        case .claude: claude
        case .codex: codex
        }
    }
}

extension RGBHex {
    /// Per-channel linear blend towards `other`; `fraction` is clamped to 0...1.
    func mix(_ other: RGBHex, _ fraction: Double) -> RGBHex {
        let t = min(max(fraction, 0), 1)
        func channel(_ shift: UInt32) -> UInt32 {
            let a = Double((value >> shift) & 0xFF), b = Double((other.value >> shift) & 0xFF)
            return UInt32((a + (b - a) * t).rounded()) << shift
        }
        return RGBHex(channel(16) | channel(8) | channel(0))
    }
}

extension Lane {
    /// The lane's accent for text and lines on a dark background: warm, part way to hot.
    var accent: RGBHex { warm.mix(hot, 0.4) }

    /// Colour of one heat cell relative to the hottest cell: cold when idle, cold → warm over
    /// the first half of `max`, warm → hot over the second half.
    func color(heat: Int, max: Int) -> RGBHex {
        guard max > 0, heat > 0 else { return cold }
        let share = min(1, Double(heat) / Double(max))
        return share <= 0.5 ? cold.mix(warm, share * 2) : warm.mix(hot, (share - 0.5) * 2)
    }
}
