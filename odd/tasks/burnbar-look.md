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
- [x] T2 Own branding: footer, Setup subtitle, quit labels, login hint, about link → Burnbar + github.com/juancasanueva/SWIFTUI_burnbar; nixfred credit kept. Route: inline. Commits 0a611c4, 0c31c68.
- [x] T3 Quit button looked disabled (tertiary grey) → secondary grey. Route: inline. Reviewed (approved). Commit bbcfd1c.
- [x] T5 Test that an in-memory live Claude reading wins over the persisted fallback. Route: delegated (with T6).
- [x] T6 Setup subscription caption colour from a typed state on SubscriptionRow, not the caption string. Route: delegated (writer trigger: 2+ files incl. tests).
- [x] T7 Persisted fallback stamped every row with the newest sample time → now the oldest, so no row looks fresher than its last reading. Route: inline (one-line fix + test). RED: persistedRowsOfDifferentAgesAreMeasuredAtTheOldest failed; GREEN: full burnbarTests TEST SUCCEEDED.
- [x] T8 By-model share was divided by the shown top models only → divided by all card tokens (`ProviderCard.share(of:)`). Route: inline. RED: compile failure (no `share`); GREEN: burnbarTests TEST SUCCEEDED.
- [x] T9 "5-hour session windows" caption said "always" even unticked → "only near the limit" when off (`SetupDisplay.fiveHourCaption`). Route: inline. RED/GREEN with T8.
- [x] T10 Sign-in missing (no Keychain item / unparseable) or rejected (401/403) no longer shows the last live or persisted rows (may be another account) and forgets `lastLive`; rate limits, network, server errors, expired token and unreadable Keychain keep them. Route: inline. RED: rejectedTokenAsksToSignInAgainAndDropsTheLastRows + aMissingSignInDropsThePersistedRows failed; GREEN: burnbarTests TEST SUCCEEDED.
- [x] T11 After a sign-out/rejection, persisted samples stay hidden on later transient failures until a live reading (`persistedUntrusted`). Route: inline. RED: persistedRowsStayHiddenAfterASignOutUntilALiveReading failed; GREEN: burnbarTests TEST SUCCEEDED.
- [x] T4 Claude card loses its limits and burndown when the usage endpoint returns 429 right after launch (in-memory `lastLive` empty) → fall back to the latest persisted samples of the current window, marked stale. Route: delegated (writer trigger: Data + tests, preparation reading). Commit 6d1f15d. Native review approved over 0c31c68..6d1f15d; follow-ups (informational): mixed-age fallback rows share one measuredAt; SetupView caption colour keys off a string literal; Codex never reports limitsLive=false, so the new non-live recording guard does not affect it.

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

- Commit: 8f4343e (feat: burn bar look for cockpit and setup). Assess: medium, slice_budget_reached. Native review granted, one lens (reliability), approved with no findings and acknowledged; reviewed boundary 8f4343e.

T4 (delegated writer, done):
- Root cause: `ClaudeLimitsClient.degraded` used only the in-memory `lastLive`; right after launch it is nil, so a 429 (or any failure) produced a snapshot with no rows → no headline, budget or burndown, although `limit-samples.jsonl` held minutes-old readings.
- Fix: `ClaudeLimitsClient` takes an optional `LimitSampleRecording`; while no live reading exists this launch, `degraded` falls back to `lastPersisted(now:)`: the newest sample per known window in `ClaudeUsageResponse.layout` (label → window minutes, so `windowDuration` is not guessed) whose reported reset is still ahead; `measuredAt` = newest such sample, `limitsLive` false, degraded status kept. Live readings win as before. `UsageStore.live` shares one `LimitSampleStore` between the client and the store; the store no longer records non-live snapshots (re-recording last known values could add samples at times a row was not read).
- Codex: not affected — `CodexRolloutCollector` reads limits from persisted rollout files (and probes untracked ones), so it never has an empty in-memory gap after launch.
- RED: new client tests failed to compile (`extra argument 'samples' in call`); the new UsageStore test failed with the record guard reverted. GREEN: full suite passes.
- Verification: `xcodebuild … -only-testing:burnbarTests test`: ** TEST SUCCEEDED **; `xcodebuild … build`: ** BUILD SUCCEEDED **.

T5 (delegated writer, done):
- `liveReadingThisLaunchWinsOverThePersistedSamples` in ClaudeLimitsClientTests: a 200 reading, then a 429 with a sample store holding different percentages (0.66 / 0.77), returns the live rows (0.42, 0.175, 0.03, 0.09) with the live `measuredAt`, not live, rate-limited status.
- Pins existing behaviour, so it passed at once. Proof it can fail: temporarily flipping `degraded` to prefer `lastPersisted(now:)` over `lastLive` made only this test fail (** TEST FAILED **, failing test `liveReadingThisLaunchWinsOverThePersistedSamples()`); the client was restored byte for byte (`git diff burnbar/Data/ClaudeLimitsClient.swift` empty).
- Verification: `xcodebuild … -only-testing:burnbarTests test`: ** TEST SUCCEEDED **.

T6 (delegated writer, done):
- `SubscriptionRow.Tone` (normal / alert / muted) and `tone` computed in `rows(cards:enabled:)` by `tone(card:isEnabled:)`, sharing `isSpent` with the caption. SetupView maps tone → lane colour / `palette.bad` / `palette.tertiary`, identical to the previous string comparison (turned off → tertiary, spent → bad, else lane, including "No plan reading").
- RED: `captionToneAlertsOnASpentBudgetAndMutesATurnedOffSubscription` failed to compile (`value of type 'SubscriptionRow' has no member 'tone'`). GREEN: full suite passes.
- Verification: `xcodebuild … -only-testing:burnbarTests test`: ** TEST SUCCEEDED **.

## Next step
User review of the renders / live app.
