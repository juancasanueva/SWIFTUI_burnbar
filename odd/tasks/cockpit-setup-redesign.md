# Feature: cockpit-setup-redesign

## Objective
Make the cockpit look like the Omarchy burnbar and the Cinderbar macOS port (screenshots/cockpit.png, cockpit2.png), and add a working Setup screen (screenshots/setup.png, setup2.png).

## Problem / Why
The current panel is a narrow 360pt stack of plain cards with no settings. Both references use a wide, dark, monospaced, multi-column cockpit and a Setup screen reached from the header.

## Scope (authorized)
- Wide multi-column cockpit: big header totals, advice banner, one card per enabled provider side by side with a lane-coloured top rule, pace badge, headline (Budget or Tokens), glow, burndown, windows, burn, token mix, by model, footer.
- Setup screen toggled from the header (SETUP / DONE), three columns. Only settings backed by real behavior, persisted in UserDefaults:
  - Subscriptions: Claude / Codex toggles (card + lane), account names toggle, read Claude plan usage toggle.
  - Strip: window (1h/3h/6h/12h/1d), cells per lane (8/12/18/24), refresh (5s/10s/30s/60s), limits refresh (2m/5m/10m/30m), ember motion, suggest next sub.
  - Cards: theme (dark/light/system), headline (budget/tokens), glow when (over/burning/spent/never), 5-hour session windows, launch at login (SMAppService).
  - Warnings: warn me again (clear advice dismissals).
- Out of scope: Grok, Kimi, local GPU lanes.

## Constraints
- Domain / Data / Presentation layering; container-presentational views (plain view state in, closures out).
- Swift Testing; test-first where a deterministic test exists (settings persistence, view-state mapping).
- Advisory ~400 authored lines per task.

## Delivery strategy
ask-on-risk. Forecast ~1400 authored lines across 4 tasks.

## Tasks
- [x] T1 Settings model + store wiring (provider toggles, strip window/cells, refresh intervals, suggest next sub, 5-hour windows, account names, read Claude limits, warn me again). Route: delegated (multi-file).
- [x] T2 Cockpit redesign (wide dark panel, header, advice banner, columns of cards, headline budget/tokens, glow, footer, theme). Route: delegated (multi-file).
- [x] T3 Setup screen (three columns, SETUP/DONE toggle, launch at login). Route: delegated (multi-file).
- [ ] T4 Ember motion in the heat strip (Reduce Motion aware) + README update. Route: delegated.

## Acceptance criteria
- Every Setup control changes visible behavior and survives relaunch.
- Unit tests pass: `xcodebuild -project burnbar.xcodeproj -scheme burnbar -destination 'platform=macOS' test`.

## Progress / Evidence
- T1 done (route: delegated, writer trigger: 2+ non-trivial files). Test-first: RED observed as compile failures for the missing settings/grid/advice APIs, then GREEN.
  - `BurnbarSettings` (Presentation, @Observable, UserDefaults-backed, injectable defaults) with option enums `StripWindow`, `CellsPerLane`, `RefreshInterval`, `LimitsRefreshInterval`, `ThemePreference`, `HeadlineMode`, `GlowWhen`.
  - Domain: `StripGrid` drives `UsageAggregator.summarize(_:now:grid:)`; `UsageSummary.window`; `AdviceEngine.advise(_:current:now:suggestingNext:)` (warnings only when off) and `isFiveHourRunningOut`.
  - Store: `UsageStore(settings:)`, `live(settings:)`, `inert(settings:)`, `settingsDidChange()` (observed via `Observations`), `warnMeAgain()`; intervals read live from settings; collectors keep 1 d of history.
  - View state: `UsageViewState.cardOptions`, `dismissedAdviceCount`, `hasDismissedAdvice`; `CardOptions` (account names, 5-hour filter) applied by `cards(now:)`; `CockpitHeader.window` / `windowLabel`.
  - Verification: `xcodebuild -project burnbar.xcodeproj -scheme burnbar -destination 'platform=macOS' -only-testing:burnbarTests test`: TEST SUCCEEDED, 315 test cases passed, 0 failed.
  - Commit: 61e263a (feat: persisted settings wired into the usage store).
  - Native review: approved and acknowledged; reviewed boundary 61e263a.
- T2 done (route: delegated, writer trigger: 2+ non-trivial files). Test-first: RED observed as compile failures for the missing `CardGlow` / headline / status APIs in `CockpitDisplayTests`, then GREEN. View layout itself has no meaningful RED; it is covered by render smoke tests and a visual check against screenshots/cockpit2.png.
  - Pure logic (`CockpitDisplay.swift`): `CardStatus` (title/detail/tone), `BudgetSummary`, `CardHeadline` via `ProviderCard.headline(_:windowLabel:)` (budget falls back to tokens), `CardGlow.glow(for:when:)`, `AdviceBanner`, `Advice.provider`, `ProviderCard.spendAdvice` / `averageRateText(window:)`, `TokenSplit.cacheReadShare`, `CockpitFormat.headlineTokens`; `LimitLine.elapsed`, `ProviderCard.buckets`.
  - Theme (`CockpitTheme.swift`): `CockpitPalette` tokens (dark/light) in `\.cockpitPalette`, `cockpitChrome()`, `cockpitBox(glow:intensity:)`, `SectionLabel`, `StatColumn`, `CockpitTextButtonStyle`, `CockpitIconButton`, `UsageBar(tick:)`; `ThemePreference.colorScheme`, `HeadlineMode.toggled`; `Lane.accent`.
  - Views: wide `CockpitView` (400 pt columns, `width(columns:)`), header with SETUP/refresh/quit, `AdviceBannerButton`, restyled cards and burndown, footer; `PanelView` holds `CockpitScreen` (.cockpit/.setup placeholder) and applies the theme.
  - Verification: `xcodebuild -project burnbar.xcodeproj -scheme burnbar -destination 'platform=macOS' -only-testing:burnbarTests test`: TEST SUCCEEDED, 352 passed, 0 failed, 1 skipped (opt-in render test, `TEST_RUNNER_BURNBAR_RENDER_PATH`).
  - Commit: 4cb82fd (feat: cinderbar-style wide cockpit).
  - Native review: approved and acknowledged; reviewed boundary 4cb82fd.
- T3 done (route: delegated, writer trigger: 2+ non-trivial files). Test-first: RED observed as compile failures in `SetupDisplayTests` (missing `LoginItemControlling`, `LoginItemStatus`, `SubscriptionRow`, `LaunchAtLoginController`), then GREEN. Layout has no meaningful RED; covered by a render smoke test and a visual check against screenshots/setup2.png.
  - Data (`LoginItem.swift`): `LoginItemStatus`, `LoginItemControlling`, `SystemLoginItem` (`SMAppService.mainApp` register/unregister), `InMemoryLoginItem` for inert runs.
  - Pure logic (`SetupDisplay.swift`): `SubscriptionRow.rows(cards:enabled:)` / `caption(card:isEnabled:)` (sentence-case status line, "Spent until it resets", "No plan reading", "Turned off"), `SetupDisplay.warningsCaption(dismissedCount:)`, `SetupOption` labels for every option enum, `LaunchAtLoginController` (`sync()`, `setEnabled(_:)` reverting on error with "Couldn't change login item: …", approval hint for `.requiresApproval`).
  - Views (`SetupView.swift`): three 290 pt columns of `SetupBox`es (rows split by thin dividers via `Group(subviews:)`), `SetupToggleRow` (small switch, lane/blue tint), `SetupPillRow` + generic `SegmentedPills` (amber selected pill, buttons with `.isSelected`, group labelled), warn-me-again pill, about box with link; `SetupControls` bindings built from `@Bindable` settings. Header reuses `CockpitHeaderView` with `isSetupOpen` (DONE, Esc). The app syncs the login item at launch, `PanelView` again when Setup opens; inert runs use the in-memory item.
  - Verification: `xcodebuild -project burnbar.xcodeproj -scheme burnbar -destination 'platform=macOS' -only-testing:burnbarTests test`: TEST SUCCEEDED, 370 passed, 0 failed, 2 skipped (opt-in renders; setup render via `TEST_RUNNER_BURNBAR_SETUP_RENDER_PATH`). ImageRenderer shows AppKit-backed switches and the link as placeholders.

## Next step
T4.
