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
