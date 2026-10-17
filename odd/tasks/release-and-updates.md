# Feature: release-and-updates

## Objective
Ship Burnbar the same way as System Monitor (/Users/juancasanueva/programming/swiftUI/system-monitor): tag-triggered signed + notarized GitHub releases, a Sparkle appcast on GitHub Pages, install via the `juancasanueva/tap` Homebrew cask, and an in-app "Check for Updates…".

## Reference (system-monitor)
- Release: `.github/workflows/release.yml` (v* tags, macos-26, Xcode 26.6, github-pages environment, public-repo and same-SHA Pages guards), `scripts/release.sh` (archive → export → package → notarize → staple → verify), `scripts/ExportOptions.plist` (developer-id, team Z3S5JK8E38), `scripts/appcast.sh` (Sparkle 2.9.6 sign_update, merge feed, Pages deploy). Version from tag, build number from GITHUB_RUN_NUMBER; project file never bumped.
- Updates: Sparkle 2.9.6 (SPM exact). Port `Domain/Ports/AppUpdating.swift`, adapter `Infrastructure/System/SparkleUpdateChecker.swift`, preference `AutomaticUpdateChecks.swift` (default off), `Domain/Services/UpdatePolicy.swift`, `Presentation/Formatting/UpdateCheckPresentation.swift`; Info.plist keys `SUFeedURL`, `SUPublicEDKey`.
- Tap: `juancasanueva/homebrew-tap` (local clone /Users/juancasanueva/programming/swiftUI/homebrew-tap), `Casks/system-monitor.rb`, cron `bump.yml` matrix pulls `releases/latest`.
- Secrets: BUILD_CERTIFICATE_BASE64, P12_PASSWORD, KEYCHAIN_PASSWORD, APPLE_API_KEY_P8, APPLE_API_KEY_ID, APPLE_API_ISSUER_ID, SPARKLE_PRIVATE_KEY.

## Decisions
- Product renamed to `Burnbar.app` (bundle id `com.juancasanueva.burnbar` unchanged). User approved.
- Sparkle key: reuse the user's existing shared EdDSA key pair (System Monitor already shares it with Home-Cellar), public key `jqReS/cOvK94pbRz/4DwMBTRMwh/0Nf5OJZ5SAfZDVs=`. Tradeoff: one leaked/lost key affects all three apps; matches the established setup and needs no new key custody.
- Feed URL: `https://juancasanueva.github.io/SWIFTUI_burnbar/appcast.xml`. Minimum system version 26.5. Asset `Burnbar-<version>.zip`.

## Scope (authorized)
App rename, Sparkle integration + Check for Updates UI, release workflow/scripts/docs in this repo, cask + bump matrix entry in the tap repo (after the first release exists).

## Tasks
- [x] T1 Rename product to Burnbar (PRODUCT_NAME), keep tests green. Route: delegated (with T2–T3).
- [x] T2 Sparkle 2.9.6 SPM + Info.plist (SUFeedURL, SUPublicEDKey) + updater port/adapter/preference/policy/presentation, tests. Route: delegated (writer trigger: many files).
- [x] T3 Setup UI: version line, "Check for Updates…", automatic checks toggle, last checked. Route: delegated with T2.
- [ ] T4 `.github/workflows/release.yml`, `scripts/release.sh`, `scripts/appcast.sh`, `scripts/ExportOptions.plist`, `RELEASING.md`, README install/update section. Route: delegated.
- [ ] T5 Repo setup (user): 7 secrets, Pages source = GitHub Actions, `github-pages` environment tag rule `v*`. Then first tag.
- [ ] T6 Tap: `Casks/burnbar.rb` + bump.yml matrix entry, after the first release. Route: inline/delegated in the tap repo.

## Acceptance criteria
- `xcodebuild -project burnbar.xcodeproj -scheme burnbar -destination 'platform=macOS' -only-testing:burnbarTests test` succeeds; app builds as Burnbar.app.
- A `v*` tag produces a notarized `Burnbar-<v>.zip` release and an appcast; `brew install --cask juancasanueva/tap/burnbar` installs it; Check for Updates finds newer releases.

## Delivery strategy
ask-on-risk. Forecast ~1500 authored lines (much ported from system-monitor, plus tests).

## Progress / Evidence
- T1 `080fe2b` chore: build the app as Burnbar.app. PRODUCT_NAME = Burnbar, PRODUCT_MODULE_NAME = burnbar (keeps `@testable import burnbar`), INFOPLIST_KEY_CFBundleDisplayName = Burnbar, TEST_HOST → Burnbar.app/…/Burnbar (both configs). RED: 3 failures in `ProjectFileTests`; GREEN: TEST SUCCEEDED; build produces Burnbar.app (CFBundleName/DisplayName/Executable = Burnbar, bundle id unchanged).
- T2 `7f5f0f3` feat: in-app updates with Sparkle. Sparkle exactVersion 2.9.6 (resolved rev ac2def28), `burnbar/Resources/Burnbar-Info.plist` merged via INFOPLIST_FILE with GENERATE_INFOPLIST_FILE = YES and excluded from the synchronized group's resources. Port: `Domain/AppUpdating.swift`, `Domain/UpdatePolicy.swift`, `Data/SparkleUpdateChecker.swift` (only Sparkle import), `Data/AutomaticUpdateChecks.swift`, `Data/InMemoryAppUpdater.swift` (inert runs), `Presentation/UpdateCheckPresentation.swift`; one updater built in `burnbarApp` via `makeUpdater(isInert:)`. RED: compile failure (`cannot find 'AutomaticUpdateChecks'/'AppUpdating'`); GREEN: TEST SUCCEEDED. Bundle: Contents/Frameworks/Sparkle.framework; Info.plist has SUFeedURL and SUPublicEDKey.
- T3 `7822dbf` feat: check for updates from setup. "Updates" group in the third column above the About note: "Check for Updates…" (disabled when it cannot check), "Automatic checks" checkbox (bound to the updater), muted "Burnbar <short> (<build>) · Never checked / Last checked …". View gets plain `SetupUpdates` values plus `SetupControls.automaticUpdateChecks`; no Sparkle in views. RED: compile failure (`cannot find 'SetupUpdates'`); GREEN: TEST SUCCEEDED. Setup width unchanged (render test unchanged).
- Verification (after T3): unit tests `** TEST SUCCEEDED **`; `xcodebuild build` `** BUILD SUCCEEDED **`; Burnbar.app embeds Sparkle.framework; `plutil -p` shows SUFeedURL and SUPublicEDKey.

## Next step
T4 (release workflow and scripts).
