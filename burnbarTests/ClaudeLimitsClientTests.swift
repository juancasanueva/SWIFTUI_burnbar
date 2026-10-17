//
//  ClaudeLimitsClientTests.swift
//  burnbarTests
//

import Foundation
import Synchronization
import Testing
@testable import burnbar

struct ClaudeLimitsClientTests {
    private let resetText = "2026-10-16T15:00:00.123456+00:00"
    private let reset = Date(timeIntervalSince1970: 1_792_162_800.123)

    private func client(_ transport: StubTransport, keychain: StubKeychain = StubKeychain()) -> ClaudeLimitsClient {
        ClaudeLimitsClient(keychain: keychain, transport: transport)
    }

    private var fullBody: String {
        usageBody(
            fiveHour: usageWindow(42, resetsAt: resetText),
            sevenDay: usageWindow(17.5, resetsAt: "2026-10-20T08:00:00Z"),
            opus: usageWindow(3, resetsAt: "2026-10-20T08:00:00.5Z"),
            sonnet: usageWindow(9, resetsAt: "2026-10-20T08:00:00Z")
        )
    }

    // MARK: Credentials

    @Test func parsesTheCredentialsItem() throws {
        let data = Data(#"{"claudeAiOauth":{"accessToken":"abc","refreshToken":"r","expiresAt":1792162800000,"scopes":["user:inference"],"subscriptionType":"pro"}}"#.utf8)
        let credentials = try #require(ClaudeCredentials(data: data))
        #expect(credentials.accessToken == "abc")
        #expect(credentials.expiresAt == Date(timeIntervalSince1970: 1_792_162_800))
        #expect(credentials.subscriptionType == "pro")
        #expect(credentials.isExpired(now: Date(timeIntervalSince1970: 1_792_162_799)) == false)
        #expect(credentials.isExpired(now: Date(timeIntervalSince1970: 1_792_162_800)))
    }

    @Test func credentialsWithoutExpiryNeverExpireAndJunkIsRejected() throws {
        let bare = try #require(ClaudeCredentials(data: Data(#"{"claudeAiOauth":{"accessToken":"abc"}}"#.utf8)))
        #expect(bare.expiresAt == nil)
        #expect(bare.isExpired(now: .distantFuture) == false)
        #expect(ClaudeCredentials(data: Data("not json".utf8)) == nil)
        #expect(ClaudeCredentials(data: Data(#"{"claudeAiOauth":{"accessToken":""}}"#.utf8)) == nil)
        #expect(ClaudeCredentials(data: Data(#"{"other":{}}"#.utf8)) == nil)
    }

    // MARK: Request and mapping

    @Test func sendsTheOAuthUsageRequest() async throws {
        let transport = StubTransport([.status(200, fullBody)])
        _ = await client(transport, keychain: StubKeychain(token: "tok-1")).limits(now: now)

        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "burnbar-macos")
    }

    @Test func mapsEveryWindowToALimitRow() async throws {
        let snapshot = try #require(await client(StubTransport([.status(200, fullBody)])).limits(now: now))
        #expect(snapshot.provider == .claude)
        #expect(snapshot.rows.map(\.label) == ["Session (5-hour)", "Weekly (7-day)", "Weekly Opus (7-day)", "Weekly Sonnet (7-day)"])
        #expect(snapshot.rows.map(\.percent) == [0.42, 0.175, 0.03, 0.09])
        #expect(snapshot.rows.map(\.windowDuration) == [300 * minute, 10080 * minute, 10080 * minute, 10080 * minute])
        #expect(abs(snapshot.rows[0].resetsAt.timeIntervalSince(reset)) < 0.001)
        #expect(snapshot.rows[2].resetsAt == TranscriptTimestamp.date(from: "2026-10-20T08:00:00.5Z"))
        #expect(snapshot.measuredAt == now)
        #expect(snapshot.limitsLive)
        #expect(snapshot.status == nil)
    }

    @Test func decodesLeniently() async throws {
        let body = #"{"five_hour":{"utilization":5,"resets_at":null},"seven_day":null,"seven_day_opus":{"resets_at":"2026-10-20T08:00:00Z"},"#
            + #""seven_day_sonnet":"unexpected","extra_usage":{"is_enabled":false}}"#
        let snapshot = try #require(await client(StubTransport([.status(200, body)])).limits(now: now))
        // A window without a reset has not started yet: it resets one full window from now.
        #expect(snapshot.rows == [LimitRow(label: "Session (5-hour)", percent: 0.05, resetsAt: now.addingTimeInterval(fiveHours), windowDuration: fiveHours)])
        #expect(snapshot.limitsLive)
    }

    @Test func anEmptyObjectIsALiveSnapshotWithoutRows() async throws {
        let snapshot = try #require(await client(StubTransport([.status(200, "{}")])).limits(now: now))
        #expect(snapshot.rows.isEmpty)
        #expect(snapshot.limitsLive)
    }

    // MARK: Caching and failures

    @Test func cachesForFiveMinutesUnlessForced() async throws {
        let transport = StubTransport([.status(200, fullBody), .status(200, fullBody), .status(200, fullBody)])
        let sut = client(transport)
        _ = await sut.limits(now: now)
        _ = await sut.limits(now: now.addingTimeInterval(299))
        #expect(await transport.requests.count == 1)

        _ = await sut.limits(now: now.addingTimeInterval(300))
        #expect(await transport.requests.count == 2)

        let forced = await sut.limits(now: now.addingTimeInterval(310), force: true)
        #expect(await transport.requests.count == 3)
        #expect(forced?.measuredAt == now.addingTimeInterval(310))
    }

    @Test func missingCredentialsReportAStatusWithoutARequest() async throws {
        let transport = StubTransport([])
        let snapshot = try #require(await client(transport, keychain: StubKeychain(.success(nil))).limits(now: now))
        #expect(snapshot.rows.isEmpty)
        #expect(snapshot.limitsLive == false)
        #expect(snapshot.status == "Claude Code sign-in not found — run claude to sign in")
        #expect(await transport.requests.isEmpty)

        let failing = try #require(await client(transport, keychain: StubKeychain(.failure(.status(-25300)))).limits(now: now))
        #expect(failing.status == "Claude Code sign-in not found — run claude to sign in")
    }

    @Test func otherKeychainFailuresSayTheItemCouldNotBeRead() async throws {
        let transport = StubTransport([])
        let snapshot = try #require(await client(transport, keychain: StubKeychain(.failure(.status(-25293)))).limits(now: now))
        #expect(snapshot.status == "Claude Code sign-in could not be read from the Keychain")
        #expect(snapshot.limitsLive == false)
        #expect(await transport.requests.isEmpty)
    }

    @Test func expiredTokenAsksToRunClaudeWithoutARequest() async throws {
        let transport = StubTransport([.status(200, fullBody)])
        let snapshot = try #require(await client(transport, keychain: StubKeychain(expiresAt: now.addingTimeInterval(-1))).limits(now: now))
        #expect(snapshot.status == "Claude Code sign-in expired — run claude to refresh")
        #expect(snapshot.limitsLive == false)
        #expect(await transport.requests.isEmpty)
    }

    @Test(arguments: [401, 403])
    func rejectedTokenAsksToSignInAgainAndDropsTheLastRows(code: Int) async throws {
        let samples = StubSampleStore()
        samples.seed(.claude, label: "Weekly (7-day)", [LimitSample(t: now, percent: 0.14, resetsAt: now.addingTimeInterval(86_400))])
        let transport = StubTransport([.status(200, fullBody), .status(code, #"{"error":"x"}"#)])
        let sut = ClaudeLimitsClient(keychain: StubKeychain(), transport: transport, samples: samples)
        _ = await sut.limits(now: now)

        // The rows may belong to another account: neither the live nor the persisted ones are shown.
        let snapshot = try #require(await sut.limits(now: now.addingTimeInterval(300)))
        #expect(snapshot.status == "Claude Code sign-in was rejected — run claude to sign in again")
        #expect(snapshot.limitsLive == false)
        #expect(snapshot.rows.isEmpty)
        #expect(snapshot.measuredAt == now.addingTimeInterval(300))
    }

    @Test func persistedRowsStayHiddenAfterASignOutUntilALiveReading() async throws {
        let samples = StubSampleStore()
        samples.seed(.claude, label: "Weekly (7-day)", [LimitSample(t: now, percent: 0.14, resetsAt: now.addingTimeInterval(86_400))])
        let transport = StubTransport([.status(401, "{}"), .failure(.timedOut), .status(200, fullBody)])
        let sut = ClaudeLimitsClient(keychain: StubKeychain(), transport: transport, samples: samples)
        _ = await sut.limits(now: now)

        let unreachable = try #require(await sut.limits(now: now.addingTimeInterval(300)))
        #expect(unreachable.rows.isEmpty)
        #expect(await sut.limits(now: now.addingTimeInterval(600))?.limitsLive == true)
    }

    @Test func aMissingSignInDropsThePersistedRows() async throws {
        let samples = StubSampleStore()
        samples.seed(.claude, label: "Weekly (7-day)", [LimitSample(t: now, percent: 0.14, resetsAt: now.addingTimeInterval(86_400))])
        let sut = ClaudeLimitsClient(keychain: StubKeychain(.success(nil)), transport: StubTransport([]), samples: samples)
        let snapshot = try #require(await sut.limits(now: now))
        #expect(snapshot.rows.isEmpty)
        #expect(snapshot.status == "Claude Code sign-in not found — run claude to sign in")
    }

    @Test func rateLimitKeepsTheLastSnapshotAndBacksOffUpToThirtyMinutes() async throws {
        let transport = StubTransport([.status(200, fullBody)] + Array(repeating: .status(429, "{}"), count: 5) + [.status(200, fullBody)])
        let sut = client(transport)
        _ = await sut.limits(now: now)

        var at = now.addingTimeInterval(300)
        let limited = try #require(await sut.limits(now: at))
        #expect(limited.rows.count == 4)
        #expect(limited.limitsLive == false)
        #expect(limited.status?.hasPrefix("Claude limits rate-limited") == true)

        // Backoff doubles: 600, 1200, 1800, 1800 s; a forced refresh does not skip it.
        for interval: TimeInterval in [600, 1200, 1800, 1800] {
            let count = await transport.requests.count
            _ = await sut.limits(now: at.addingTimeInterval(interval - 1), force: true)
            #expect(await transport.requests.count == count)
            at = at.addingTimeInterval(interval)
            _ = await sut.limits(now: at)
            #expect(await transport.requests.count == count + 1)
        }

        // Success resets the interval to five minutes.
        #expect(await sut.limits(now: at.addingTimeInterval(1800))?.limitsLive == true)
        let count = await transport.requests.count
        _ = await sut.limits(now: at.addingTimeInterval(1800 + 300))
        #expect(await transport.requests.count == count + 1)
    }

    @Test func rateLimitBeforeAnyLiveReadingShowsTheLastPersistedSamples() async throws {
        let weeklyReset = now.addingTimeInterval(3 * 86_400)
        let samples = StubSampleStore()
        samples.seed(.claude, label: "Weekly (7-day)", [
            LimitSample(t: now.addingTimeInterval(-1200), percent: 0.12, resetsAt: weeklyReset),
            LimitSample(t: now.addingTimeInterval(-600), percent: 0.14, resetsAt: weeklyReset),
        ])
        // A window that has reset since, and one without a known reset, are not shown.
        samples.seed(.claude, label: "Session (5-hour)", [LimitSample(t: now.addingTimeInterval(-7200), percent: 0.5, resetsAt: now.addingTimeInterval(-60))])
        samples.seed(.claude, label: "Weekly Opus (7-day)", [LimitSample(t: now.addingTimeInterval(-600), percent: 0.02)])
        samples.seed(.codex, label: "Weekly (7-day)", [LimitSample(t: now.addingTimeInterval(-60), percent: 0.9, resetsAt: weeklyReset)])
        let transport = StubTransport([.status(429, "{}"), .status(200, fullBody)])
        let sut = ClaudeLimitsClient(keychain: StubKeychain(), transport: transport, samples: samples)

        let limited = try #require(await sut.limits(now: now))
        #expect(limited.rows == [LimitRow(label: "Weekly (7-day)", percent: 0.14, resetsAt: weeklyReset, windowDuration: 10080 * minute)])
        #expect(limited.measuredAt == now.addingTimeInterval(-600))
        #expect(limited.limitsLive == false)
        #expect(limited.status?.hasPrefix("Claude limits rate-limited") == true)

        // Once the backoff passes, the live reading wins.
        let live = try #require(await sut.limits(now: now.addingTimeInterval(601)))
        #expect(live.limitsLive)
        #expect(live.rows.count == 4)
    }

    @Test func persistedRowsOfDifferentAgesAreMeasuredAtTheOldest() async throws {
        let samples = StubSampleStore()
        samples.seed(.claude, label: "Weekly (7-day)", [LimitSample(t: now.addingTimeInterval(-600), percent: 0.14, resetsAt: now.addingTimeInterval(3 * 86_400))])
        samples.seed(.claude, label: "Session (5-hour)", [LimitSample(t: now.addingTimeInterval(-3600), percent: 0.3, resetsAt: now.addingTimeInterval(3600))])
        let sut = ClaudeLimitsClient(keychain: StubKeychain(), transport: StubTransport([.status(429, "{}")]), samples: samples)

        let limited = try #require(await sut.limits(now: now))
        #expect(limited.rows.count == 2)
        // No row is shown as fresher than its own last reading.
        #expect(limited.measuredAt == now.addingTimeInterval(-3600))
    }

    @Test func liveReadingThisLaunchWinsOverThePersistedSamples() async throws {
        let weeklyReset = now.addingTimeInterval(3 * 86_400)
        let samples = StubSampleStore()
        samples.seed(.claude, label: "Weekly (7-day)", [LimitSample(t: now.addingTimeInterval(-600), percent: 0.66, resetsAt: weeklyReset)])
        samples.seed(.claude, label: "Session (5-hour)", [LimitSample(t: now.addingTimeInterval(-600), percent: 0.77, resetsAt: weeklyReset)])
        let transport = StubTransport([.status(200, fullBody), .status(429, "{}")])
        let sut = ClaudeLimitsClient(keychain: StubKeychain(), transport: transport, samples: samples)
        let live = try #require(await sut.limits(now: now))

        let limited = try #require(await sut.limits(now: now.addingTimeInterval(300)))
        #expect(limited.rows == live.rows)
        #expect(limited.rows.map(\.percent) == [0.42, 0.175, 0.03, 0.09])
        #expect(limited.measuredAt == now)
        #expect(limited.limitsLive == false)
        #expect(limited.status?.hasPrefix("Claude limits rate-limited") == true)
    }

    @Test func failureWithoutLiveReadingOrSamplesHasNoRows() async throws {
        let sut = ClaudeLimitsClient(keychain: StubKeychain(), transport: StubTransport([.status(429, "{}")]), samples: StubSampleStore())
        let snapshot = try #require(await sut.limits(now: now))
        #expect(snapshot.rows.isEmpty)
        #expect(snapshot.measuredAt == now)
        #expect(snapshot.limitsLive == false)
    }

    @Test func networkErrorKeepsTheLastSnapshotWithAStatus() async throws {
        let transport = StubTransport([.status(200, fullBody), .failure(.timedOut)])
        let sut = client(transport)
        _ = await sut.limits(now: now)

        let snapshot = try #require(await sut.limits(now: now.addingTimeInterval(300)))
        #expect(snapshot.rows.count == 4)
        #expect(snapshot.measuredAt == now)
        #expect(snapshot.limitsLive == false)
        #expect(snapshot.status == "Claude limits unreachable — showing the last known values")
    }

    @Test func unexpectedResponsesKeepTheLastSnapshot() async throws {
        let transport = StubTransport([.status(200, fullBody), .status(500, "oops"), .status(200, "[1,2]")])
        let sut = client(transport)
        _ = await sut.limits(now: now)

        let serverError = try #require(await sut.limits(now: now.addingTimeInterval(300)))
        #expect(serverError.status == "Claude limits unavailable (HTTP 500)")
        #expect(serverError.rows.count == 4)
        let garbage = try #require(await sut.limits(now: now.addingTimeInterval(600)))
        #expect(garbage.status == "Claude limits response not understood")
        #expect(garbage.rows.count == 4)
    }

    // MARK: Keychain access and overlap

    @Test func overlappingCallsSendOneRequest() async throws {
        let transport = StubTransport([.status(200, fullBody), .status(200, fullBody)], delay: .milliseconds(200))
        let sut = client(transport)
        async let first = sut.limits(now: now)
        async let second = sut.limits(now: now, force: true)
        let (a, b) = await (first, second)
        #expect(await transport.requests.count == 1)
        #expect(a == b)
    }

    @Test func overlappingCallsReadTheKeychainOnce() async throws {
        let keychain = SlowKeychain(holds: true)
        let sut = ClaudeLimitsClient(keychain: keychain, transport: StubTransport([.status(200, fullBody)]))
        async let first = sut.limits(now: now)
        async let second = sut.limits(now: now, force: true)
        try await waitUntil { keychain.reads > 0 }
        keychain.release()
        _ = await (first, second)
        #expect(keychain.reads == 1)
    }

    @Test func aSlowKeychainReadDoesNotBlockTheClient() async throws {
        let keychain = SlowKeychain(holds: true)
        let sut = ClaudeLimitsClient(keychain: keychain, transport: StubTransport([.status(200, fullBody)]))
        let pending = Task { await sut.limits(now: now) }
        try await waitUntil { keychain.reads > 0 }
        // The actor answers while the Keychain read is still held.
        #expect(await sut.isRefreshing)
        #expect(keychain.released == false)
        keychain.release()
        #expect(await pending.value?.limitsLive == true)
        #expect(await sut.isRefreshing == false)
    }

    @Test func theTokenIsCachedUntilRejected() async throws {
        let keychain = SlowKeychain()
        let transport = StubTransport([.status(200, fullBody), .status(200, fullBody), .status(401, "{}"), .status(200, fullBody)])
        let sut = ClaudeLimitsClient(keychain: keychain, transport: transport)
        _ = await sut.limits(now: now)
        _ = await sut.limits(now: now.addingTimeInterval(300))
        #expect(keychain.reads == 1)

        // A 401 forgets the token, so the next refresh reads the Keychain again.
        _ = await sut.limits(now: now.addingTimeInterval(600))
        #expect(keychain.reads == 1)
        #expect(await sut.limits(now: now.addingTimeInterval(900))?.limitsLive == true)
        #expect(keychain.reads == 2)
    }

    @Test func anExpiredCachedTokenIsReadAgain() async throws {
        let transport = StubTransport([.status(200, fullBody), .status(200, fullBody)])
        let keychain = StubKeychain(expiresAt: now.addingTimeInterval(400))
        let sut = client(transport, keychain: keychain)
        _ = await sut.limits(now: now)
        // The cached token has expired and the Keychain still holds the same one.
        let expired = try #require(await sut.limits(now: now.addingTimeInterval(450)))
        #expect(expired.status == "Claude Code sign-in expired — run claude to refresh")
        #expect(await transport.requests.count == 1)
    }

    @Test func aKeychainFailureIsRetriedOnlyWhenForced() async throws {
        let keychain = CountingFailingKeychain()
        let sut = ClaudeLimitsClient(keychain: keychain, transport: StubTransport([]))
        _ = await sut.limits(now: now)
        _ = await sut.limits(now: now.addingTimeInterval(300))
        #expect(keychain.reads == 1)
        let forced = await sut.limits(now: now.addingTimeInterval(310), force: true)
        #expect(keychain.reads == 2)
        #expect(forced?.status == "Claude Code sign-in could not be read from the Keychain")
    }

    // MARK: Retry-After

    @Test func retryAfterSecondsLongerThanTheBackoffIsHonored() async throws {
        let transport = StubTransport([.headers(429, "{}", ["Retry-After": "1500"]), .status(200, fullBody)])
        let sut = client(transport)
        let limited = await sut.limits(now: now)
        #expect(limited?.status == "Claude limits rate-limited — retrying in 25 min")
        _ = await sut.limits(now: now.addingTimeInterval(1499), force: true)
        #expect(await transport.requests.count == 1)
        _ = await sut.limits(now: now.addingTimeInterval(1500))
        #expect(await transport.requests.count == 2)
    }

    @Test func retryAfterDateIsHonored() async throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        let date = formatter.string(from: now.addingTimeInterval(900))
        let transport = StubTransport([.headers(429, "{}", ["Retry-After": date]), .status(200, fullBody)])
        let sut = client(transport)
        _ = await sut.limits(now: now)
        _ = await sut.limits(now: now.addingTimeInterval(899), force: true)
        #expect(await transport.requests.count == 1)
        _ = await sut.limits(now: now.addingTimeInterval(900))
        #expect(await transport.requests.count == 2)
    }

    @Test func retryAfterIsCappedAndNeverShortensTheBackoff() async throws {
        let transport = StubTransport([
            .headers(429, "{}", ["Retry-After": "10800"]),
            .headers(429, "{}", ["Retry-After": "60"]),
            .status(200, fullBody),
        ])
        let sut = client(transport)
        _ = await sut.limits(now: now)
        _ = await sut.limits(now: now.addingTimeInterval(1799), force: true)
        #expect(await transport.requests.count == 1)
        var at = now.addingTimeInterval(1800)
        _ = await sut.limits(now: at)
        #expect(await transport.requests.count == 2)

        // Retry-After 60 s is shorter than the doubled local backoff (1200 s), which wins.
        _ = await sut.limits(now: at.addingTimeInterval(1199), force: true)
        #expect(await transport.requests.count == 2)
        at = at.addingTimeInterval(1200)
        _ = await sut.limits(now: at)
        #expect(await transport.requests.count == 3)
    }

    @Test(arguments: [("120", 120.0), ("garbage", nil), ("-5", nil)] as [(String, Double?)])
    func parsesRetryAfter(value: String, expected: Double?) {
        #expect(ClaudeLimitsClient.retryAfter(value, now: now) == expected)
    }
}

/// Fails every read with a non-not-found status, counting reads.
final class CountingFailingKeychain: KeychainReading {
    private let count = Mutex(0)
    var reads: Int { count.withLock { $0 } }

    func genericPassword(service: String) throws -> Data? {
        count.withLock { $0 += 1 }
        throw KeychainError.status(-25293)
    }
}

/// Polls `condition` every 10 ms, failing after `timeout`.
func waitUntil(timeout: Duration = .seconds(3), _ condition: @Sendable () -> Bool) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while !condition() {
        guard clock.now < deadline else {
            Issue.record("Timed out waiting for a condition")
            return
        }
        try await Task.sleep(for: .milliseconds(10))
    }
}
