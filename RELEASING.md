# Releasing Burnbar

How a version of Burnbar becomes something a stranger can download, and what is true of that
build by construction rather than by hope. The pipeline is ported from System Monitor
(`SWIFTUI_system_monitor`) and keeps its guarantees; the names are Burnbar's.

## 1. How a release happens

A pushed `v*` tag is the **only** thing that publishes. There is no manual step between the
push and the published asset, and no other trigger on the workflow: it holds a Developer ID
certificate and an App Store Connect key, so any trigger a contributor could reach would hand
both to whoever reached it.

Three files, split by ownership:

| File | Owns |
|---|---|
| `.github/workflows/release.yml` | The runner, the secrets, the ephemeral keychain, cleanup, and publication: everything that only exists on CI |
| `scripts/release.sh` | The build sequence: archive → export → package → notarize → staple → verify |
| `scripts/appcast.sh` | The update feed: download and verify the pinned signing tool, fetch the live feed, sign one zip, merge one item, emit |

`scripts/release.sh` is a **rehearsal path, not a publishing path**. It contains no
version-control and no release-management invocation, so it can neither select a repository
nor publish, tag, or retract anything. Running it locally produces the same artifact and
publishes nothing. `scripts/appcast.sh` carries the same prohibition, and
`AppcastScriptContractTests` asserts it.

The workflow invokes the build script **one phase per named step**, so a failure names the
stage that failed.

## 2. Prerequisites

None of these block merging the pipeline. All of them block the first release.

1. **The repository must be public before the first tag.** Release assets are only
   anonymously downloadable from a public repository. The workflow refuses to run on a
   private repository, before any signing or notarization work.
2. **A Developer ID Application certificate**, exported as a `.p12` **with its private key**.
   Xcode → Settings → Accounts → Manage Certificates → **+** → Developer ID Application, then
   export from Keychain Access. The one System Monitor uses works; it belongs to the team, not
   the app.
3. **An App Store Connect API key** (`.p8`), **Developer** role. Note its key id and issuer id.
4. **Seven repository secrets**, named exactly:

   | Secret | Value |
   |---|---|
   | `BUILD_CERTIFICATE_BASE64` | `base64 -i DeveloperID.p12` |
   | `P12_PASSWORD` | The password used when exporting the certificate |
   | `KEYCHAIN_PASSWORD` | Any strong string; it protects the run's throwaway keychain |
   | `APPLE_API_KEY_P8` | The full contents of the App Store Connect `.p8` file |
   | `APPLE_API_KEY_ID` | The key id |
   | `APPLE_API_ISSUER_ID` | The issuer id |
   | `SPARKLE_PRIVATE_KEY` | The shared EdDSA private key (see 7) |

5. **Actions enabled**, with permission to write releases. The workflow declares
   `contents: write` and uses the run's own `GITHUB_TOKEN`; no personal token is involved.
6. **GitHub Pages enabled, with source = GitHub Actions.** Settings → Pages → Build and
   deployment → Source: **GitHub Actions**. This serves
   `https://juancasanueva.github.io/SWIFTUI_burnbar/appcast.xml`, the feed every installed copy
   reads (`SUFeedURL` in `burnbar/Resources/Burnbar-Info.plist`).

   The `github-pages` deployment environment must also allow tag refs. It is created with a
   **branch** policy and this job runs on **tags** (`v*`): Settings → Environments →
   `github-pages` → Deployment branches and tags → add a **tag** rule matching `v*`. Without it
   the deploy step fails at the end of an otherwise successful release.
7. **The Sparkle EdDSA key pair.**

   **Burnbar shares the existing key pair with System Monitor and Home-Cellar.** The public
   half is already committed, in `burnbar/Resources/Burnbar-Info.plist` as `SUPublicEDKey`, and
   it is what every installed copy checks an update's signature against.
   `SPARKLE_PRIVATE_KEY` is the **same private key** those repositories' release jobs use. If
   it is not at hand, export it from the login Keychain of the machine that generated it with
   `./bin/generate_keys -x sparkle-private.key` from the Sparkle 2.9.6 distribution (pinned by
   digest `52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192`), store it
   offline, then `rm -P sparkle-private.key`.

   **This is a one-way door.** Losing the private key permanently severs the update channel
   for every copy already installed of **all three** apps: rotation requires shipping a new
   `SUPublicEDKey` through some channel that is not Sparkle. A leaked key lets an attacker sign
   updates for all three. The public key is *not* a secret and must never be handled as one.

The team identifier `Z3S5JK8E38` lives in the repository and is not a secret.

## 3. Tag-and-release runbook

**Preflight.** `main` up to date, the suite green, and the version you are about to tag is the
version you mean.

```sh
git tag -a v1.0.0 -m "Burnbar 1.0.0"
git push origin v1.0.0
```

Then watch the run under the repository's Actions tab:

| Stage | What it does | What stops the run |
|---|---|---|
| Private-repository gate | Refuses to publish an unreachable asset | The repository is not public |
| Distinct-commit gate | Asks the Pages deployments API whether this commit already deployed the feed | It has (stable tags only) |
| Pin Xcode | Selects `Xcode_26.6.app`, the SDK a macOS 26.5 deployment target needs | The runner image no longer carries it |
| Archive | Release archive stamped with the tag and the run number | Any build failure |
| Export | Developer ID export, then gates version and architecture | `CFBundleShortVersionString` ≠ the tag, or any slice other than `arm64` |
| Package | `ditto` into `Burnbar-<version>.zip` | — |
| Notarize | `notarytool submit --wait` | Apple rejects it; the diagnostic log is printed |
| Staple | Staples the ticket and repackages | Stapling fails |
| Verify | Gates against the copy extracted from the zip | Any gate |
| Fetch the Sparkle tools | `scripts/appcast.sh tools`: downloads the pinned Sparkle 2.9.6 tarball, checks its SHA-256 and extracts it into `$RUNNER_TEMP`, before anything is public (stable tags only) | A download failure after bounded retries, or a digest mismatch |
| Fetch the live feed | `scripts/appcast.sh fetch`: fetches and validates the live feed into `$RUNNER_TEMP`, before anything is public (stable tags only) | Anything but a usable 200 or a 404, after bounded retries |
| Publish | `gh release create --verify-tag --generate-notes` | — |
| Build the appcast | Reads the pre-fetched feed and tools (never downloads either again), signs the zip and writes the whole feed outside the checkout | The pre-fetched feed or tools are missing, or signing or emission fails (stable tags only) |
| Configure Pages / Upload / Deploy | Deploys that directory under this commit | The deployment fails |
| Cleanup | Deletes the keychain and the API key, always | — |

**Every stable release must be cut from its own commit.** Pages keys a deployment by the
commit SHA and silently ignores a second deployment of the same commit, so a second stable
tag on one commit would publish a release the feed never learns about. The distinct-commit
gate stops that before anything is signed.

**The live feed is never replaced on a guess.** `scripts/appcast.sh` treats only an HTTP 404
as "no feed yet" (the first release) and starts an empty channel. A DNS failure, a timeout, a
5xx or any other status, and a 200 whose body is empty or has no `</channel>`, all stop the
run, so a transient error can never replace the live feed with a one-item feed.

**Everything the appcast needs from the network is downloaded before the release is
published.** "Fetch the Sparkle tools" and "Fetch the live feed" run right before Publish, so a
github.com, Pages or CDN failure stops the run while nothing is public and the tag can simply be
re-run or re-tagged. Both go through one download helper. Each attempt is bounded
(`--connect-timeout 10`, and `--max-time 60` for the feed, 300 for the tarball). Transient
failures are retried, four attempts in all, 5 s, 10 s and 20 s apart: curl exits 6 (DNS), 7
(connect), 16 (HTTP/2 framing), 18 (partial transfer), 28 (timeout), 35 (TLS handshake), 52, 55 and 56 (dropped connection), 92 (HTTP/2 stream), and HTTP 408,
429 and 5xx. A 200 and a 404 are never retried, and any other 4xx or curl exit is refused at once; for the
tarball a 404 is a failure too. The tarball must match the pinned SHA-256 before it is
extracted. A failed fetch also removes what an earlier run left at its destination, so a stale
feed or tools directory is never read as this run's. The build step after Publish reads both
and does not touch the network again.

### When a run fails

Where the run stopped decides what is already public. `gh release create` is the line.

**Before Publish** (both gates, Pin Xcode, keychain, Archive, Export, Package, Notarize,
Staple, Verify, signing evidence, Fetch the Sparkle tools, Fetch the live feed): nothing was
published. A transient download failure needs no fix: **Re-run failed jobs**. Otherwise fix the
cause, delete the tag and tag again; the same commit is fine.

```sh
git push --delete origin v1.0.0
git tag -d v1.0.0
```

**After Publish** (Build the appcast, Configure Pages, Upload, Deploy): none of them downloads
anything any more, so what fails here is signing (a wrong or missing `SPARKLE_PRIVATE_KEY`, a
signing-tool output the script refuses), emission, or the Pages upload and deployment. The GitHub release and
its zip **already exist** and are `releases/latest`, but the feed was not updated, so no
installed copy is offered the version. The Homebrew tap's scheduled bump, or anyone browsing
the releases page, may already have picked it up. There is no step-level retry: **Re-run
failed jobs** re-runs the whole job, which stops at Publish because the release for that tag
already exists. Pick one:

1. **Cut the next patch version (preferred).** Leave the release as it is, fix the cause on a
   new commit, and tag `v1.0.1` there. Its run publishes `v1.0.1` and a feed that offers it;
   the stranded `v1.0.0` simply never has a feed item. Nothing already seen is withdrawn.
2. **Delete the release and re-run, when the cause was outside the repository** (a transient
   network or Pages failure, the `github-pages` tag rule, a secret). Delete only the release,
   keep the tag, then **Re-run failed jobs**. The re-run uses the same tag, commit, workflow
   file and run number (so the same build number), and notarizes again:

   ```sh
   gh release delete v1.0.0 --repo juancasanueva/SWIFTUI_burnbar --yes
   ```

3. **Delete the release and the tag, and re-tag**, when the fix needs a code change but the
   version must stay `1.0.0`. Delete both, then tag the fixing commit:

   ```sh
   gh release delete v1.0.0 --repo juancasanueva/SWIFTUI_burnbar --yes --cleanup-tag
   git tag -d v1.0.0
   ```

   The new run has a higher build number and a freshly notarized zip with different bytes.
   Anyone who already downloaded `1.0.0`, and a cask that already bumped to it, hold a zip
   whose checksum no longer matches the asset of that name.

Options 2 and 3 carry the same risk: between the first publish and the deletion, clients may
have seen `v1.0.0`. They are only safe because the feed never pointed at it. If the Deploy step
itself started and failed, the deployments API can report a non-empty status for the commit,
and the distinct-commit gate then refuses any re-run or re-tag on it: use option 1.

`scripts/appcast.sh` can be run locally (see 5) to reproduce an appcast failure and inspect the
feed it would emit, but it does not deploy. The release job is the only path to Pages.

**Never delete or unflag a release the feed points at.** Once a version has a feed item,
installed copies may already be updating to its asset. A bad release is withdrawn by cutting a
new patch tag.

A tag containing a hyphen (`v0.0.1-rc.1`) publishes as a **prerelease** and adds **no feed
entry**, so an installed copy is never offered one. Use it to rehearse against the real
repository.

## 4. Version policy

**The tag is the source of truth.** `MARKETING_VERSION` is the tag without its `v`, and
`CURRENT_PROJECT_VERSION` is `GITHUB_RUN_NUMBER`, which only increases, so `CFBundleVersion`
grows on every release, including a re-cut tag. The project file is never bumped per release;
a local Release build reports `1.0 (1)` unless both are overridden on the command line.

## 5. Local rehearsal

```sh
# `all` includes `notarize`, so the App Store Connect key is required.
VERSION=1.0.0 BUILD_NUMBER=1 \
ASC_KEY_PATH=~/.private_keys/AuthKey_XXXXXXXXXX.p8 ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=<issuer-uuid> \
scripts/release.sh all

# Without the key, rehearse a phase that needs none:
VERSION=1.0.0 BUILD_NUMBER=1 scripts/release.sh archive
```

Phases: `archive`, `export`, `package`, `notarize`, `staple`, `verify`, `all`. Output goes to
`build/` (override with `RELEASE_BUILD_DIR`). `SIGNING_STYLE` defaults to `manual` and must
agree with `signingStyle` in `scripts/ExportOptions.plist`.

The feed step rehearses the same way and needs no repository:

```sh
VERSION=1.0.0 BUILD_NUMBER=1 GITHUB_REF_NAME=v1.0.0 \
ASSET_URL=https://github.com/juancasanueva/SWIFTUI_burnbar/releases/download/v1.0.0/Burnbar-1.0.0.zip \
ZIP_PATH=build/Burnbar-1.0.0.zip \
FEED_URL=https://juancasanueva.github.io/SWIFTUI_burnbar/appcast.xml \
OUTPUT_DIR=/tmp/site SPARKLE_PRIVATE_KEY="$(cat ~/offline/sparkle-private.key)" scripts/appcast.sh
```

Without `CURRENT_FEED_FILE` the build fetches the feed itself, and without `SPARKLE_TOOLS_DIR`
it downloads and verifies the Sparkle tools itself, with the same timeouts, retries and
refusals. To rehearse CI's steps, or only check that the downloads work:

```sh
GITHUB_REF_NAME=v1.0.0 SPARKLE_TOOLS_DIR=/tmp/sparkle-tools scripts/appcast.sh tools
GITHUB_REF_NAME=v1.0.0 FEED_URL=https://juancasanueva.github.io/SWIFTUI_burnbar/appcast.xml \
CURRENT_FEED_FILE=/tmp/current-appcast.xml scripts/appcast.sh fetch
```

Then pass the same `SPARKLE_TOOLS_DIR` and `CURRENT_FEED_FILE` to the build above instead of
`FEED_URL`. `tools` only ever replaces a directory it wrote itself (it carries a
`.pinned-sha256` marker); it refuses any other existing, non-empty directory.
`FETCH_RETRY_DELAY` (a non-negative integer, default 5; any other value stops the script at once) sets the first retry delay of both downloads.

## 6. Entitlements and hardened runtime

Hardened runtime **on**, app sandbox **off**. Burnbar was already unsandboxed (it reads
`~/.claude`, `~/.codex` and another app's Keychain item), and Sparkle needs it too: it replaces
the app bundle in place. Both settings are asserted by `UpdateProjectFileTests`, and the
delivered bundle is re-checked at release time. There is no `.entitlements` file and no
hardened-runtime exception (`allow-jit`, `allow-unsigned-executable-memory`,
`disable-library-validation`).

The app builds for Apple Silicon only: `ARCHS = arm64` is pinned in both app configurations
(asserted by `UpdateProjectFileTests`) and passed again on the archive line.

## 7. The contract the delivery channels inherit

| Property | Value |
|---|---|
| Asset URL | `https://github.com/juancasanueva/SWIFTUI_burnbar/releases/download/v<version>/Burnbar-<version>.zip` |
| Asset name | `Burnbar-<version>.zip`, exactly one per release |
| Bundle inside it | `Burnbar.app`, display name `Burnbar`, executable `Contents/MacOS/Burnbar` |
| Bundle identifier | `com.juancasanueva.burnbar` |
| Signature | Developer ID Application, team `Z3S5JK8E38`, hardened runtime, notarized and stapled |
| Floor | macOS 26.5, Apple Silicon (`arm64`) |
| Update feed | `https://juancasanueva.github.io/SWIFTUI_burnbar/appcast.xml`, republished on every **stable** tag |

The feed's minimum system version is `MINIMUM_SYSTEM_VERSION="26.5"` in `scripts/appcast.sh`
and `AppcastDocument.expectedMinimumSystemVersion` in the app; `AppcastScriptContractTests`
fails when they disagree. `ReleasePipelineNamesTests` pins the feed URL, asset name, scheme and
product against what the app declares.

**A Pages deploy is a full-site replacement.** The release job is the only thing that may
deploy to Pages; a second workflow deploying a site would overwrite `appcast.xml`.

## 8. The Homebrew tap

The cask points at the same `Burnbar-<version>.zip`; there is no second artifact.

| Thing | Value |
|---|---|
| Tap repository | `juancasanueva/homebrew-tap` (shared with System Monitor and Home-Cellar) |
| Cask | `Casks/burnbar.rb`, token `burnbar` |
| Install | `brew install --cask juancasanueva/tap/burnbar` |
| Installed path | `/Applications/Burnbar.app` |

The cask declares `auto_updates true` (Sparkle owns updates) and `depends_on arch: :arm64`.
Its `zap` stanza should cover `~/Library/Application Support/burnbar` (the limit-sample
store) and the `com.juancasanueva.burnbar` preferences, caches and HTTP storage. Burnbar
creates no Keychain items; it only reads Claude Code's.

**Adding it, after the first release exists:** create `Casks/burnbar.rb` modelled on
`Casks/system-monitor.rb`, and add a matrix entry to the tap's `.github/workflows/bump.yml`:

```yaml
          - cask: burnbar
            repo: SWIFTUI_burnbar
            asset: Burnbar
```

`bump.yml` then **pulls** `releases/latest` on its schedule, takes the checksum from the
published asset, and commits only when the version changed. Nothing in this repository pushes
to the tap.

### Manual fallback

If the tap's Actions are down:

```sh
gh release view --repo juancasanueva/SWIFTUI_burnbar --json tagName --jq .tagName
curl -fsSLO https://github.com/juancasanueva/SWIFTUI_burnbar/releases/download/v<version>/Burnbar-<version>.zip
shasum -a 256 Burnbar-<version>.zip
# edit version and sha256 in Casks/burnbar.rb, then from the tapped checkout:
brew style juancasanueva/tap
brew audit --cask --online --strict juancasanueva/tap/burnbar
git commit -am "chore(cask): burnbar <version>" && git push
```

Never commit a checksum that the online audit has not verified.

## 9. Troubleshooting

**Notarization rejected.** The run prints the `notarytool log` for the submission. Usual
causes: an unsigned nested binary, a missing hardened-runtime flag, or the wrong identity.
Nothing was published; fix, delete the tag, tag again.

**Keychain import failed.** `BUILD_CERTIFICATE_BASE64` is not a `.p12` exported **with its
private key**, or `P12_PASSWORD` does not match it.

**Pin Xcode failed.** The runner image dropped `/Applications/Xcode_26.6.app`. Update the pin
rather than lowering the deployment target.

**The run stopped at the distinct-commit gate.** This commit already deployed the feed. Put
the new version on a new commit and tag that.

**Fetch the live feed failed.** The live feed answered something other than a usable 200 or a
404, or could not be reached, on every attempt. Nothing was published: check the feed URL in
a browser, then re-run the job or re-tag ("Before Publish" in 3).

**Fetch the Sparkle tools failed.** The Sparkle 2.9.6 tarball could not be downloaded on
every attempt, or it did not match the pinned SHA-256. Nothing was published. A download
failure is usually transient: re-run the job. A digest mismatch means the asset on
github.com changed; do not update the digest without finding out why ("Before Publish" in 3).

**Build the appcast failed.** The feed and the tools were fetched before Publish, so this is
signing (the `SPARKLE_PRIVATE_KEY` secret), emission, or a missing pre-fetched feed or tools
directory. The release already exists; follow "After Publish" in 3.

**The run is green but the feed still shows the previous version.** Usually the CDN; compare
`last-modified` on the feed URL. A hyphenated tag skips every publication step by design.
