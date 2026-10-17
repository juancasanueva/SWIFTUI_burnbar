import Foundation
import Testing

@testable import burnbar

/// Reads `scripts/appcast.sh` off disk.
///
/// Self-contained so the publication half rolls back by deleting one script and
/// one test file.
nonisolated enum AppcastScriptSources {

    static let scriptPath = "scripts/appcast.sh"

    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // burnbarTests
            .deletingLastPathComponent()   // repository root
    }

    static var scriptURL: URL { repositoryRoot.appendingPathComponent(scriptPath) }

    static func script() throws -> String {
        try String(contentsOf: scriptURL, encoding: .utf8)
    }

    /// Every invocation of `command` as a **command token**.
    ///
    /// A bare substring search is not good enough. `gh` occurs inside
    /// "github.com", which this script names in every enclosure URL, and `git`
    /// occurs inside "gitignored". A prohibition that fires on prose, or on a
    /// hostname, is a prohibition someone eventually weakens to shut it up — so
    /// it fires only on an actual invocation: start of line, or after whitespace,
    /// `;`, `|`, `&` or `(`, and followed by whitespace or the end of the line.
    static func commandInvocations(of command: String, in text: String) -> [String] {
        let pattern = "(?:^|[\\s;|&(])\(NSRegularExpression.escapedPattern(for: command))(?=\\s|$)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        return text.split(separator: "\n", omittingEmptySubsequences: false).flatMap { line -> [String] in
            let text = String(line)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return regex.matches(in: text, range: range).compactMap { match in
                guard let matched = Range(match.range, in: text) else { return nil }
                let start = text[matched].hasPrefix(command) ? matched.lowerBound
                    : text.index(after: matched.lowerBound)
                return String(text[start...])
            }
        }
    }

    static func lines(naming needle: String, in text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains(needle) }
    }
}

// release-distribution — what the appcast script is allowed to do, and what it
// must never do.
//
// Structural assertions over text, because the properties that matter here are
// absences — "it cannot publish", "it cannot trace itself", "the key is never
// written anywhere" — and an absence in a shell script is only provable by
// reading it.
@Suite("Appcast script contract", .timeLimit(.minutes(1)))
struct AppcastScriptContractTests {

    static let signPipeline = "printf '%s' \"$SPARKLE_PRIVATE_KEY\" |"

    // MARK: - The script's own posture

    /// It exists, it runs, and it fails loudly.
    @Test("The appcast script is executable and fails on the first error")
    func theScriptIsExecutableAndFailsLoudly() throws {
        let path = AppcastScriptSources.scriptURL.path

        #expect(FileManager.default.fileExists(atPath: path))
        #expect(FileManager.default.isExecutableFile(atPath: path))
        #expect(try AppcastScriptSources.script().contains("set -euo pipefail"))
    }

    /// It cannot publish, tag, retract, or pick a different repository.
    ///
    /// The release workflow's own guarantee is that it can only ever *create* a
    /// release: exactly one `gh release create`, zero `git`. A script invoked
    /// from that workflow with a `git` or a second `gh` in it would move the
    /// guarantee without touching the test that guards it, which is precisely why
    /// the script is asserted separately.
    @Test("The appcast script contains no git and no gh invocation")
    func theScriptCannotPublishOrSelectARepository() throws {
        let script = try AppcastScriptSources.script()

        #expect(AppcastScriptSources.commandInvocations(of: "git", in: script) == [])
        #expect(AppcastScriptSources.commandInvocations(of: "gh", in: script) == [])
        // The reader is only meaningful if it can find an invocation at all.
        #expect(!AppcastScriptSources.commandInvocations(of: "curl", in: script).isEmpty)
    }

    /// It never traces its own commands.
    ///
    /// `set -x` would echo the signing pipeline into the job log, and the signing
    /// pipeline is where the private key is.
    ///
    /// Matched as a command token rather than as a substring: the script explains
    /// in a comment *why* it must never trace itself, and a prohibition that
    /// fires on prose about itself is a prohibition someone eventually deletes to
    /// shut it up.
    @Test("The appcast script never traces itself")
    func theScriptNeverTracesItself() throws {
        let script = try AppcastScriptSources.script()

        #expect(AppcastScriptSources.commandInvocations(of: "set -x", in: script) == [])
        // The reader is only meaningful if it can see a `set` that is really there.
        #expect(!AppcastScriptSources.commandInvocations(of: "set", in: script).isEmpty)
    }

    /// The signing tool is pinned by version **and** by digest.
    ///
    /// A tampered `sign_update` would sign the release with an attacker's key and
    /// every installed copy would accept the result, because the client only
    /// checks the signature against the key in its own bundle. The version alone
    /// does not prevent that; the digest does, and the verification aborts before
    /// anything is signed.
    @Test("The signing tool is pinned to 2.9.6 by a sha256 literal")
    func theSigningToolIsPinnedByDigest() throws {
        let script = try AppcastScriptSources.script()
        let digest = try NSRegularExpression(pattern: "\\b[0-9a-f]{64}\\b")
        let range = NSRange(script.startIndex..<script.endIndex, in: script)

        #expect(script.contains("2.9.6"))
        #expect(digest.numberOfMatches(in: script, range: range) == 1)
        #expect(script.contains("shasum -a 256"))
    }

    /// The private key reaches the tool on **stdin** and touches nothing else.
    ///
    /// Never a file, never a command argument, never a redirection target. The
    /// signing tool reads `--ed-key-file -` from standard input precisely so the
    /// key can come from a secret environment binding without ever being written
    /// down, which satisfies the invariant by construction rather than by
    /// remembering to clean up afterwards.
    @Test("The private key is only ever piped on stdin")
    func thePrivateKeyIsOnlyEverPipedOnStdin() throws {
        let script = try AppcastScriptSources.script()
        let naming = AppcastScriptSources.lines(naming: "SPARKLE_PRIVATE_KEY", in: script)

        #expect(!naming.isEmpty)
        for line in naming {
            let isComment = line.trimmingCharacters(in: .whitespaces).hasPrefix("#")
            #expect(isComment || line.contains(Self.signPipeline), "unsafe use: \(line)")
            #expect(!line.contains(">"), "the key must never be a redirection target: \(line)")
        }
        #expect(script.contains("--ed-key-file -"))
        #expect(!script.contains("--ed-key-file \""))
    }

    // MARK: - The emitter and the validator agree on names

    /// Every name the offline validator requires appears in the emitter.
    ///
    /// **Honest about being textual.** The fixtures the validator is tested
    /// against are hand-authored, because running this script inside
    /// `xcodebuild test` would need the signing tool, a private key and network
    /// egress — three things this project forbids. So this proves the emitter and
    /// the validator agree on **names**, not on bytes. That limitation is stated
    /// rather than smoothed over.
    @Test("The emitter names every field the offline validator requires")
    func theEmitterNamesEveryFieldTheValidatorRequires() throws {
        let script = try AppcastScriptSources.script()
        let required = [
            "sparkle:edSignature",
            "length=",
            "sparkle:version",
            "sparkle:shortVersionString",
            "sparkle:minimumSystemVersion",
            "<enclosure"
        ]

        for name in required {
            #expect(script.contains(name), "the emitter never writes \(name)")
        }
    }

    /// The emitter's floor and the validator's floor are the same string.
    ///
    /// Asserted against `AppcastDocument.expectedMinimumSystemVersion` rather
    /// than against a literal repeated in this file: two constants that must
    /// agree are only kept in step by a test that reads both. A feed emitted with
    /// a floor the validator rejects is a feed every installed copy refuses, and
    /// it would only be discovered after publication.
    @Test("The emitter's minimum system version is the one the validator requires")
    func theEmitterAndTheValidatorAgreeOnTheMinimumSystemVersion() throws {
        let script = try AppcastScriptSources.script()
        let expected = AppcastDocument.expectedMinimumSystemVersion

        #expect(expected == "26.5")
        #expect(
            script.contains("MINIMUM_SYSTEM_VERSION=\"\(expected)\""),
            "the emitter must declare MINIMUM_SYSTEM_VERSION=\"\(expected)\""
        )
    }

    // MARK: - Fetching the live feed

    /// The script's `# --- fetch` section, up to the next section marker.
    static func fetchSection(of script: String) throws -> String {
        let start = try #require(script.range(of: "# --- fetch"))
        let rest = script[start.upperBound...]
        let end = try #require(rest.range(of: "# --- tool"))
        return String(rest[rest.startIndex..<end.lowerBound])
    }

    /// The feed is fetched by exactly one `curl` call site.
    ///
    /// The behavioural tests below run the real script against a stubbed `curl`,
    /// so they only prove something about production if every feed fetch goes
    /// through the one call site they exercise.
    @Test("The live feed has exactly one curl call site, in the fetch section")
    func theLiveFeedHasExactlyOneCurlCallSite() throws {
        let script = try AppcastScriptSources.script()
        let fetch = try Self.fetchSection(of: script)
        let feedFetches = { (text: String) in
            AppcastScriptSources.commandInvocations(of: "curl", in: text).filter { $0.contains("$FEED_URL") }
        }

        #expect(feedFetches(script).count == 1)
        #expect(feedFetches(fetch).count == 1)
    }

    /// Only a 404 means "no feed yet", and it is never retried.
    ///
    /// The merged feed replaces the live one wholesale, so a fetch failure read
    /// as "first release" would publish a one-item feed and strand every
    /// installed copy on a version it skipped.
    @Test("A 404 starts an empty channel after one attempt")
    func a404StartsAnEmptyChannelAfterOneAttempt() throws {
        let run = try FeedFetchHarness.run(responses: ["404"])

        #expect(run.exitStatus == 0, "\(run.log)")
        #expect(run.curlCalls.count == 1)
        let feed = try #require(run.feed.flatMap { String(data: $0, encoding: .utf8) })
        #expect(feed.contains("<channel>"))
        #expect(feed.contains("</channel>"))
        #expect(!feed.contains("<item>"))
        // The heredoc is tab-indented and `<<-` strips the tabs: an unstripped
        // tab before the declaration would make the document malformed XML.
        #expect(feed.hasPrefix("<?xml"))
    }

    /// A usable 200 is kept byte for byte.
    @Test("A valid 200 is kept as served")
    func aValid200IsKeptAsServed() throws {
        let run = try FeedFetchHarness.run(responses: ["200"], body: FeedFetchHarness.liveFeed)

        #expect(run.exitStatus == 0, "\(run.log)")
        #expect(run.curlCalls.count == 1)
        #expect(run.feed == Data(FeedFetchHarness.liveFeed.utf8))
    }

    /// Every other outcome exits non-zero and leaves no feed file behind.
    ///
    /// curl failing (DNS, connection refused, timeout), a 5xx that never
    /// recovers, another 4xx, and a 200 whose body is empty or is not a feed.
    @Test("Any other fetch outcome exits non-zero and writes nothing", arguments: FeedFetchFailure.all)
    func anyOtherFetchOutcomeExitsNonZero(_ failure: FeedFetchFailure) throws {
        let run = try FeedFetchHarness.run(responses: failure.responses, body: failure.body)

        #expect(run.exitStatus != 0, "\(run.log)")
        #expect(run.feed == nil, "a refused fetch must not leave a feed file")
        #expect(run.curlCalls.count == failure.expectedAttempts)
    }

    /// A transient failure is retried, and a later success is kept.
    @Test("A transient 5xx or timeout is retried until the feed answers")
    func aTransientFailureIsRetried() throws {
        let run = try FeedFetchHarness.run(responses: ["503", "exit28", "200"], body: FeedFetchHarness.liveFeed)

        #expect(run.exitStatus == 0, "\(run.log)")
        #expect(run.curlCalls.count == 3)
        #expect(run.feed == Data(FeedFetchHarness.liveFeed.utf8))
    }

    /// Every attempt is bounded in time and reads the status code itself.
    ///
    /// `-f` is refused because it folds a 404 and a 503 into one exit status, and
    /// curl's own `--retry-all-errors` because it would retry a 404.
    @Test("Every attempt carries connect and total timeouts and no -f")
    func everyAttemptIsBounded() throws {
        let run = try FeedFetchHarness.run(responses: ["503", "200"], body: FeedFetchHarness.liveFeed)

        #expect(run.curlCalls.count == 2)
        for call in run.curlCalls {
            #expect(call.contains("--connect-timeout"), "\(call)")
            #expect(call.contains("--max-time"), "\(call)")
            #expect(call.contains("%{http_code}"), "\(call)")
            #expect(!call.contains("--retry-all-errors"), "\(call)")
            let clusters = call.filter { $0.hasPrefix("-") && !$0.hasPrefix("--") }
            #expect(!clusters.contains { $0.contains("f") }, "curl -f hides which failure it was: \(call)")
        }
    }

    /// The build reads the pre-fetched feed and never fetches it again.
    ///
    /// In CI the feed is fetched before the release is published; the build step
    /// runs after. A missing pre-fetched file must stop the build rather than
    /// quietly fetch a second time after the release is already public.
    @Test("The build refuses a missing pre-fetched feed without fetching")
    func theBuildRefusesAMissingPreFetchedFeed() throws {
        let run = try FeedFetchHarness.run(mode: nil, responses: ["200"], body: FeedFetchHarness.liveFeed)

        #expect(run.exitStatus != 0, "\(run.log)")
        #expect(run.curlCalls.isEmpty)
    }

    /// A prerelease tag fetches nothing, in either mode.
    @Test("A prerelease tag skips the fetch")
    func aPrereleaseTagSkipsTheFetch() throws {
        let run = try FeedFetchHarness.run(responses: ["200"], body: FeedFetchHarness.liveFeed, tag: "v1.0.0-beta.1")

        #expect(run.exitStatus == 0, "\(run.log)")
        #expect(run.curlCalls.isEmpty)
        #expect(run.feed == nil)
    }

    /// A prerelease tag produces no feed item at all.
    ///
    /// The same literal guard the release workflow uses, restated in the script
    /// so running it by hand behaves identically to running it in CI. A
    /// prerelease that reached the feed would be offered to every stable user,
    /// which the version comparison alone would not prevent.
    @Test("A prerelease tag exits before writing anything")
    func aPrereleaseTagExitsBeforeWritingAnything() throws {
        let script = try AppcastScriptSources.script()

        #expect(script.contains("case \"$GITHUB_REF_NAME\" in"))
        #expect(script.contains("*-*)"))
        #expect(script.contains("exit 0"))
    }
}

// MARK: - Running the real fetch against controlled responses

/// One refused fetch outcome, and how many attempts it is allowed.
nonisolated struct FeedFetchFailure: Sendable, CustomTestStringConvertible {
    let name: String
    let responses: [String]
    let body: String?
    let expectedAttempts: Int

    var testDescription: String { name }

    static let all: [FeedFetchFailure] = [
        FeedFetchFailure(name: "503 on every attempt", responses: ["503"], body: nil, expectedAttempts: 4),
        FeedFetchFailure(name: "connection refused", responses: ["exit7"], body: nil, expectedAttempts: 4),
        FeedFetchFailure(name: "DNS failure", responses: ["exit6"], body: nil, expectedAttempts: 4),
        FeedFetchFailure(name: "timeout", responses: ["exit28"], body: nil, expectedAttempts: 4),
        FeedFetchFailure(name: "403, never retried", responses: ["403", "200"], body: FeedFetchHarness.liveFeed,
                         expectedAttempts: 1),
        FeedFetchFailure(name: "empty 200", responses: ["200"], body: "", expectedAttempts: 1),
        FeedFetchFailure(name: "200 without </channel>", responses: ["200"], body: "<html>maintenance</html>",
                         expectedAttempts: 1)
    ]
}

/// Runs `scripts/appcast.sh` with a stubbed `curl` first on `PATH`.
///
/// A stub rather than a local HTTP server: it needs no port, no network and no
/// timing, so every outcome — including DNS failures and timeouts, which a
/// server cannot produce on demand — is deterministic inside `xcodebuild test`.
/// The stub answers the n-th call with the n-th response (the last one repeats),
/// and records each call's arguments one per line. A response is an HTTP status
/// or `exit<N>`, a curl failure with exit status N.
nonisolated enum FeedFetchHarness {

    struct Run {
        let exitStatus: Int32
        let feed: Data?
        let curlCalls: [[String]]
        let log: String
    }

    static let liveFeed = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
            <channel>
                <title>Burnbar</title>
                <item><title>Version 1.0.0</title></item>
            </channel>
        </rss>

        """

    static let stubCurl = #"""
        #!/bin/bash
        set -eu
        printf '%s\x1f' "$@" >> "$STUB_DIR/calls"
        printf '\n' >> "$STUB_DIR/calls"
        n="$(wc -l < "$STUB_DIR/calls")"
        read -r -a responses <<< "$STUB_RESPONSES"
        i=$(( n <= ${#responses[@]} ? n - 1 : ${#responses[@]} - 1 ))
        response="${responses[$i]}"
        out=""
        while [ $# -gt 0 ]; do
            case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
        done
        case "$response" in
            exit*) echo "curl: (${response#exit}) stubbed failure" >&2; printf '000'; exit "${response#exit}" ;;
            200) if [ -f "$STUB_DIR/body" ]; then cp "$STUB_DIR/body" "$out"; fi ;;
            *) printf '<html>%s</html>' "$response" > "$out" ;;
        esac
        printf '%s' "$response"
        """#

    /// `mode` is the script's first argument; `nil` runs the build.
    static func run(
        mode: String? = "fetch",
        responses: [String],
        body: String? = nil,
        tag: String = "v1.0.0"
    ) throws -> Run {
        let fileManager = FileManager.default
        let dir = fileManager.temporaryDirectory.appendingPathComponent("feed-fetch-\(UUID().uuidString)")
        let stubs = dir.appendingPathComponent("bin")
        try fileManager.createDirectory(at: stubs, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: dir) }

        let curl = stubs.appendingPathComponent("curl")
        try Data(stubCurl.utf8).write(to: curl)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: curl.path)
        if let body { try Data(body.utf8).write(to: dir.appendingPathComponent("body")) }

        let feedFile = dir.appendingPathComponent("prefetched/current.xml")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [AppcastScriptSources.scriptURL.path] + (mode.map { [$0] } ?? [])
        process.currentDirectoryURL = dir
        process.environment = [
            "PATH": "\(stubs.path):/usr/bin:/bin",
            "HOME": dir.path,
            "STUB_DIR": dir.path,
            "STUB_RESPONSES": responses.joined(separator: " "),
            "GITHUB_REF_NAME": tag,
            "FEED_URL": "https://feed.invalid/appcast.xml",
            "CURRENT_FEED_FILE": feedFile.path,
            "FEED_FETCH_RETRY_DELAY": "0",
            "VERSION": "1.0.0",
            "BUILD_NUMBER": "1",
            "ASSET_URL": "https://example.invalid/Burnbar-1.0.0.zip",
            "ZIP_PATH": dir.appendingPathComponent("Burnbar-1.0.0.zip").path,
            "OUTPUT_DIR": dir.appendingPathComponent("site").path,
            "SPARKLE_PRIVATE_KEY": "not-a-key"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let calls = (try? String(contentsOf: dir.appendingPathComponent("calls"), encoding: .utf8)) ?? ""
        return Run(
            exitStatus: process.terminationStatus,
            feed: mode == nil ? nil : try? Data(contentsOf: feedFile),
            curlCalls: calls.split(separator: "\n").map { line in
                line.split(separator: "\u{1F}", omittingEmptySubsequences: false).dropLast().map(String.init)
            },
            log: String(decoding: output, as: UTF8.self)
        )
    }
}
