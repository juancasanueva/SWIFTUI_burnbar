//
//  ClaudeLimitsClientTests.swift
//  burnbarTests
//

import Foundation
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
    func rejectedTokenAsksToSignInAgainAndKeepsTheLastRows(code: Int) async throws {
        let transport = StubTransport([.status(200, fullBody), .status(code, #"{"error":"x"}"#)])
        let sut = client(transport)
        _ = await sut.limits(now: now)

        let snapshot = try #require(await sut.limits(now: now.addingTimeInterval(300)))
        #expect(snapshot.status == "Claude Code sign-in was rejected — run claude to sign in again")
        #expect(snapshot.limitsLive == false)
        #expect(snapshot.rows.count == 4)
        #expect(snapshot.measuredAt == now)
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
}
