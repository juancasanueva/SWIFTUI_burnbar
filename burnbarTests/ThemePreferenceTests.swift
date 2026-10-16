//
//  ThemePreferenceTests.swift
//  burnbarTests
//

import SwiftUI
import Testing
@testable import burnbar

struct ThemePreferenceTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func darkAndLightIgnoreTheSystem(system: ColorScheme) {
        #expect(ThemePreference.dark.resolved(system: system) == .dark)
        #expect(ThemePreference.light.resolved(system: system) == .light)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func systemFollowsTheSystem(system: ColorScheme) {
        #expect(ThemePreference.system.resolved(system: system) == system)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func theResolvedSchemePicksThePalette(system: ColorScheme) {
        #expect(CockpitPalette(ThemePreference.light.resolved(system: system)) == .light)
        #expect(CockpitPalette(ThemePreference.dark.resolved(system: system)) == .dark)
    }
}
