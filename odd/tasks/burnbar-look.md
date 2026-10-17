# Feature: burnbar-look

## Objective
Shift the cockpit and Setup look and feel toward the Omarchy Burn Bar (screenshots/cockpit.png, setup.png) and away from Cinderbar (cockpit2.png, setup2.png). Behavior and settings stay as they are.

## Problem / Why
The current UI follows Cinderbar: rounded macOS cards, bold sans display numbers, switches and amber segmented pills. The user prefers Burn Bar's terminal aesthetic.

## Target look (Burn Bar)
- All monospaced text; uppercase, letter-spaced section labels; lowercase sentence captions.
- Deep navy/indigo background, thin full lane-coloured card border (not just a top rule), small corner radius.
- Glowing cards get a soft coloured outer glow and a tinted border.
- Header: flame + big lane-coloured monospaced total, then uppercase tracked meta ("FRONTIER TOKENS BURNED · LAST 24H · N TURNS · N SESSIONS"); SETUP text + refresh on the right.
- Advice banner: single row, "▶ USE X NEXT" in tracked caps, details inline, bordered box.
- Cards: lane name uppercase in lane colour, outlined pill status chip, a bordered headline strip ("BANKED 49% …"), big % in lane colour with small two-line caption, BURNDOWN · WEEKLY section label.
- Setup: SETUP title + subtitle, "Back to the cockpit" on the right; three columns of flat rows on a slightly lighter row fill; checkbox and radio glyphs instead of switches/segmented pills; caption right-aligned in muted text; history window as outlined capsule buttons.

## Scope (authorized)
Presentation-only restyle: CockpitTheme, PanelView, ProviderCardView, BurndownChartView, SetupView (+ their tests if APIs change). No domain or settings changes.

## Constraints
- Container-presentational; existing tests keep passing.
- Advisory ~400 authored lines per task.

## Delivery strategy
ask-on-risk. Forecast ~400-600 authored lines, 1 task.

## Tasks
- [x] T1 Burn Bar restyle of cockpit + setup. Route: delegated (writer trigger: 2+ non-trivial files).

## Acceptance criteria
- Rendered cockpit and setup (opt-in render tests) read as Burn Bar, not Cinderbar.
- `xcodebuild -project burnbar.xcodeproj -scheme burnbar -destination 'platform=macOS' -only-testing:burnbarTests test` succeeds.

## Progress / Evidence
T1 (delegated writer, done):
- Theme: deep navy palette (panel #1A1B2C, card #1D1E31, row #24253A), lavender-grey secondary, orange accent; 4 pt card radius; thin full lane-coloured border, glow = tinted border + faint tinted fill + soft shadow. Monospaced, tracked uppercase section labels; StatColumn value-over-label.
- Cockpit: flame + orange monospaced total + tracked meta ("TOKENS BURNED · LAST 6 H · N TURNS · N SESSIONS"); SETUP + refresh, quiet quit. Advice banner as one bordered row "▶ USE CODEX NEXT" + inline detail. Cards: lane-coloured uppercase name, outlined capsule chip, bordered status strip, big % in lane colour with two-line caption and "⇄ tokens" hint, "BURNDOWN · WEEKLY (7-DAY)" with "-- even pace" and reset caption, flat window gauges, BURN · TOKENS / MIN, token-mix share bar, models with share %, turns/sessions footer. Footer hint line ("the dashed diagonal is an even spend…").
- Setup: SETUP title + subtitle, "Back to the cockpit" (Esc); three columns of group labels and flat rows: checkbox rows (real `Toggle` with a glyph style), radio rows (`.isSelected`) for headline and glow with captions, outlined capsule choices (theme, history window, cells, refresh, limits refresh). Link replaced by a plain button (ImageRenderer drew `Link` as a placeholder).
- Tests: SetupViewTests width formula uses `SetupView.columnSpacing`.
- Verification: `xcodebuild … -only-testing:burnbarTests test`: ** TEST SUCCEEDED **; `xcodebuild … build`: ** BUILD SUCCEEDED **. Test-first exception: pure visual restyle, render check stands in.
- Renders: /private/tmp/claude-501/-Users-juancasanueva-programming-swiftUI-burnbar/f0f4e176-7b2c-47ee-8ca9-bd9883c8955a/scratchpad/cockpit.png and setup.png (before: cockpit-before.png, setup-before.png).

## Next step
User review of the renders / live app.
