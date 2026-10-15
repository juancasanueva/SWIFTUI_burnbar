# Feature: macos-burnbar

## Objective
Native macOS menu bar port of the Omarchy plugin https://github.com/nixfred/burnbar, scoped to Claude + Codex.

## Problem / Why
Upstream is Linux-only (Quickshell QML + bash collector + Omarchy usage records). On macOS we need a native app that reads the same local transcripts and fetches plan limits itself.

## Scope (authorized)
- Claude + Codex lanes only. Grok, Kimi, Zcode and local Ollama/GPU are out of scope (future, behind the same provider protocol).
- Menu bar heat strip + advice chip, cockpit panel (popover window), pace/limit math.
- No dollar cost: upstream computes none.

## Constraints
- macOS 26.5, Swift 5 mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Xcode 26.6, file-system-synchronized groups (new files auto-included).
- App Sandbox must be OFF (reads `~/.claude`, `~/.codex`, and another app's Keychain item). `LSUIElement = YES` (menu bar only).
- Architecture: Domain (pure models + math, no I/O) / Data (collectors, clients, stores) / Presentation (SwiftUI, @Observable). Protocols at boundaries for testability.
- Tests: Swift Testing in `burnbarTests`.

## Upstream reference spec (condensed)
### Claude burn
- Files: `~/.claude/projects/**/*.jsonl`. Parse only lines containing `"usage"`.
- Fields: `timestamp` (ISO8601, fractional secs), `message.id`, `message.model`, `message.usage.{input_tokens, cache_creation_input_tokens, output_tokens, cache_read_input_tokens}`.
- Dedupe by `message.id`, keep the revision with the largest token total.
- Heat tokens = input + cacheWrite + output. Cache reads tracked separately, excluded from heat.
- Session = file. Turn = unique message.
### Codex burn
- Files: `~/.codex/sessions/**/rollout-*.jsonl`. Lines with `payload.type == "token_count"`.
- `payload.info.total_token_usage` / `last_token_usage`: `{input_tokens, cached_input_tokens, cache_write_input_tokens?, output_tokens}`. `info` may be null.
- Burn = delta of successive cumulative totals per file; identical repeat skipped; a decreasing total = reset → use `last_token_usage`. Fresh input = input − cached.
### Codex limits (local, verified on this machine)
- Same token_count lines carry `payload.rate_limits.{primary, secondary}.{used_percent (0-100), window_minutes, resets_at (unix secs)}`. Use the newest record. primary=300 min ("Session (5-hour)"), secondary=10080 min ("Weekly (7-day)").
### Claude limits
- Keychain generic password service `Claude Code-credentials` (exists on this machine), JSON `{"claudeAiOauth":{"accessToken","expiresAt",...}}`.
- `GET https://api.anthropic.com/api/oauth/usage`, headers `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`. Response (unverified until runtime): `{five_hour:{utilization 0-100, resets_at ISO}, seven_day:{...}, seven_day_opus?:{...}}`. Must fail gracefully (status text), refresh every 300 s.
### Window / buckets
- Window 360 min, 12 buckets × 30 min aligned to grid; headline totals over exact trailing window; trailing rates m5, m60.
### Pace math (per limit row: percent p in 0..1, window L, reset r)
- elapsed e = (L − (r − now))/L; ratio = p/e (only when e ≥ 0.01); allowancePerHour = (1 − p)/hoursLeft.
- ratePerHour = least-squares slope over own percent samples (last 2 h or 10% of window if shorter, span ≥ 10 min). Samples persisted every 5 min or on change.
- projected = p + rate·hoursLeft; dryAt = now + (1 − p)/rate; backOnPaceAt = r − L(1 − p).
- Daily ceiling for windows ≥ 36 h: todayCeiling = (1 − p)·min(1, 24/hoursLeft).
- Gift: drop ≥ 3% with same reset → rebase window.
- Verdict: ratio > 1.5 WAY OVER, > 1.05 OVER, > 0.9 AT PACE, else ON TRACK.
- Stage: 1 ratio > 1.05, 2 > 1.5, 3 > 2.5, 4 p ≥ 0.995.
- Gauge colour: ≥ 0.9 red, ≥ 0.75 yellow, else green; pulse ≥ 0.9.
- banked = e − p; over = behind > 0.01 && p/e > 1.05. Pick next sub: banked ≥ 2%, switch only if 1.15× better. "Use it now" when time left ≤ min(72 h, 15% window). Blocked when 5-hour ≥ 90% or full within 0.5 h.
- Stale after max(900 s, 3·limitsRefresh). Row with passed resetsAt → unknown.
### UI
- Lane colours (cold/warm/hot): Claude #4A2113/#C4542A/#FF8A4B; Codex #0C3E33/#12977A/#2BE8B0; amber #FFC46B; white-hot #FFF6EC. Error = solid red.
- Bar: per-lane 12-bucket heat strip, weekly gauges at ends, one advice chip (e.g. "CLAUDE REST 8H", "SPENT", "CLAUDE 5-HOUR OUT IN 40M", "USE CODEX NEXT"); click dismisses until worse (persisted).
- Panel: header (window tokens, turns, sessions); per-sub card: verdict, what-to-do, headline, burndown chart, windows, burn rates, token mix, by-model, account label.
- Account: Claude `~/.claude.json` `oauthAccount.{emailAddress, displayName, organizationName}`; Codex `~/.codex/auth.json` `tokens.id_token` JWT payload `email`/`name` (unverified decode).
- Refresh: collector every 5 s (incremental), limits every 300 s and on panel open.

## Delivery strategy
`ask-on-risk` → chain strategy `stacked-to-main` (user choice, 2026-10-16). Default branch `main` (renamed from master). Remote `origin` = github.com/juancasanueva/SWIFTUI_burnbar (push/PR = user decision).
- Slice 1 (PR 1): bd7f26c T1 + c7d0e73 T2 — native review lineage review-70c25ffbf3b22016 (granted).

## Tasks
- [x] T1 App shell: MenuBarExtra (window style), LSUIElement, sandbox off, remove SwiftData template, folder skeleton. Route: delegated (multi-file).
- [x] T2 Domain: models, PaceCalculator, verdict/stage/colour, bucketing, advice picker — pure + Swift Testing (TDD). Route: delegated.
- [x] T3 Data: Claude transcript collector (incremental, dedupe) + tests. Route: delegated (multi-file: parser, collector, protocol, tests).
- [x] T4 Data: Codex collector (cumulative deltas + rate_limits) + tests. Route: delegated (multi-file: parser, collector, limits protocol, domain snapshot, tests).
- [ ] T5 Data: Claude limits client (Keychain + OAuth usage), limit-sample store, account labels. Route: delegated.
- [ ] T6 Presentation: menu bar heat strip + gauges + advice chip, refresh loop. Route: delegated.
- [ ] T7 Presentation: cockpit panel cards + Swift Charts burndown. Route: delegated.

## Acceptance criteria
- App runs as menu-bar-only, shows Claude + Codex strips from real local data, Codex limits from rollout files, Claude limits from OAuth endpoint (or a clear status message on failure).
- Pace math unit tested against the formulas above.
- `xcodebuild test` passes.

## Checks
- `xcodebuild -project burnbar.xcodeproj -scheme burnbar -destination 'platform=macOS' build test`

## Progress / Evidence
- 2026-10-16: base commit 83857c2 (template). Branch `feat/macos-burnbar`. RDD: on (global).
- T1 done (delegated writer): MenuBarExtra .window shell, sandbox off, LSUIElement, SwiftData template removed, App/Domain/Data/Presentation skeleton (comment-only layer files; .gitkeep collides as a bundle resource). Check: `xcodebuild ... build test` -> TEST SUCCEEDED (unit + UI launch test). Commit bd7f26c.
- T2 done (delegated writer, TDD): Domain models, UsageAggregator, PaceCalculator (+ isStale), Verdict/Stage/GaugeLevel, AdviceEngine, LanePalette (RGBHex). RED: test target failed to compile (cannot find Provider/UsageEvent/TokenSplit/LimitRow/Pace/PaceCalculator/LimitSample). GREEN: `xcodebuild ... build test` -> TEST SUCCEEDED, 66 test cases passed (incl. UI launch test). Interpretations: gift drop (>= 3% between consecutive samples of the current window) rebases only the rate fit; samples before the window start (previous reset) are ignored; negative slopes clamp to 0; all subs blocked -> SPENT, current blocked/over with no >= 2% banked alternative -> REST (longest of blocking 5-hour reset, full weekly reset, back-on-pace); unknown weekly counts as 0 banked. Commit: `feat: domain usage aggregation and pace math`.
- Review advisories (slice 1) fixed (delegated writer, TDD): 5-hour "full within 0.5 h" blocking now also requires dryAt < resetsAt (isBlocked and restInterval share one helper); Pace.percent returns the clamped share; added tests for weekly >= 99.5% blocking and REST until the weekly reset. RED: `dryAfterResetIsNotBlocked`, `percentIsClampedLikeDerivedValues` failed. GREEN: `xcodebuild ... build test` -> TEST SUCCEEDED, 70 test cases passed. Commit: `fix: guard pace edge cases from review`.
- T3 done (delegated writer, TDD): `UsageCollector` protocol (Data), pure `ClaudeTranscriptParser` (prefilter on `"usage"`, small Decodable structs, ISO8601 with/without fractional seconds, `sessionId` else file name, kimi/moonshot excluded, zero-token synthetic turns skipped, dedupe keeps the largest four-count total), `ClaudeTranscriptCollector` actor (recursive `*.jsonl` scan, per-file offset + size + mtime, only new bytes, partial trailing line waits, shrunk file re-read from 0, untracked files modified before the cutoff skipped, turns pruned past 360 + 30 min margin, vanished files forgotten). RED: test target failed to compile (cannot find ClaudeTranscriptCollector / ClaudeTurn / ClaudeTranscriptParser). GREEN: `xcodebuild ... build test` -> TEST SUCCEEDED, 95 test cases passed (25 new). Fixtures are synthetic. Commit: `feat: claude transcript collector`.
- Review advisories (T3 collector) fixed (delegated writer, TDD): shared `JSONLTailer` (Data, nonisolated) owns per-file offset, size, mtime, inode and a fingerprint (first 1 KiB + 1 KiB before the offset), reads in 1 MiB chunks delivering complete lines, holds back a partial trailing line. Rewrite = shrunk below offset, inode changed, or fingerprint mismatch -> re-read from 0. Policy: turns are kept per file; a rewritten file's turns are dropped and re-ingested from its new content, a deleted file's turns are dropped; dedupe by message id runs across files, so a message also present in another file survives. RED: `JSONLTailerTests` failed to compile (no `JSONLTailer`); collector tests `rereadsAFileThatShrank` (now expects only the new content), `rereadsAFileRewrittenInPlaceWithLargerContent`, `rereadsAFileReplacedAtomically`, `forgetsTurnsOfDeletedFiles` failed. GREEN: `xcodebuild ... build test` -> TEST SUCCEEDED, 107 test cases passed. Commit 8317974 `fix: detect rewritten transcripts in collector`.
- T4 done (delegated writer, TDD): pure `CodexRolloutParser` (prefilter on `"token_count"`/`"turn_context"`, `event_msg` token_count -> total/last usage, `info: null` keeps rate limits, missing `cache_write_input_tokens` -> 0, unix-seconds `resets_at`), `CodexBurnTracker` (per-file deltas of cumulative totals; identical repeat skipped; any count decreasing = reset -> `last_token_usage`; split input = input - cached, cacheWrite, output, cacheRead = cached; model from the latest `turn_context`, else "codex"; session = file name), `CodexRolloutCollector` actor (`UsageCollector` + new `LimitsSource` protocol `limits(now:) async -> LimitSnapshot?`) reusing `JSONLTailer` (rewrite -> file's events re-derived, deletion -> dropped, prune past window + margin). Limits = newest `rate_limits` record by timestamp across tailed files; when none is known, the 3 newest untracked rollout files are probed once each via their last 256 KiB (`JSONLTailer.lastLines`). Domain: `LimitSnapshot {provider, rows, measuredAt}`, `LimitRow.label(windowMinutes:)` (300 -> "Session (5-hour)", 10080 -> "Weekly (7-day)", 1440 -> "Daily (1-day)", other days "Window (N-day)"); `TranscriptTimestamp` shared by both parsers. Real rollout key shapes checked on this machine (keys only); fixtures synthetic. RED: test target failed to compile (cannot find CodexRolloutCollector / CodexTokenUsage). GREEN: `xcodebuild ... build test` -> TEST SUCCEEDED, 138 test cases passed (31 new). Commit: `feat: codex rollout collector`.
- Review advisories (T4 Codex) fixed (delegated writer, TDD): limits are tracked per source file (tailed files by URL, probed files by exact version), so a rewritten file's record is derived again and a deleted/changed/now-tailed file's record is dropped and the next newest takes over (re-probing when none is left). Probe order covered: most recently modified first even when an older file holds a newer record, each file version probed once, at most `probeCount` per refresh (injectable `probeCount` + `onProbe` hook). `JSONLTailer.lastLines` direct tests: cut first line skipped, no newline in a mid-file range -> nothing, trailing line without newline now delivered (probed files are not being appended to; a torn line fails to decode). RED: `limitsAreReDerivedWhenTheirFileIsRewritten`, `limitsFallBackWhenTheirFileIsDeleted`, `probedLimitsAreDroppedWithTheirFileAndOthersAreProbed`, `lastLinesIncludesATrailingLineWithoutNewline` failed (probe-order tests passed as characterization). GREEN: `xcodebuild ... build test` -> TEST SUCCEEDED, 147 test cases passed. Commit: `test: cover codex limits probe and tailer edges`.

## Next step
T5.
