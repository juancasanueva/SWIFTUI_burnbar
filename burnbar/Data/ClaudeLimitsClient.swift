//
//  ClaudeLimitsClient.swift
//  burnbar
//

import Foundation

/// Fetches Claude plan limits from the OAuth usage endpoint with Claude Code's own sign-in.
///
/// The access token comes from the `Claude Code-credentials` Keychain item; burnbar never
/// refreshes it (an expired token asks the user to run `claude`). Results are cached for
/// `refreshInterval` unless a refresh is forced. HTTP 429 backs off by doubling the interval up
/// to `maxBackoff`, and even a forced refresh waits it out. Every failure keeps the last known
/// rows (with their original `measuredAt`) and explains itself in `LimitSnapshot.status`.
actor ClaudeLimitsClient: LimitsSource {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"
    static let defaultRefreshInterval: TimeInterval = 300
    static let defaultMaxBackoff: TimeInterval = 30 * 60

    /// User-facing status texts.
    nonisolated enum Status {
        static let signInNotFound = "Claude Code sign-in not found — run claude to sign in"
        static let keychainUnreadable = "Claude Code sign-in could not be read from the Keychain"
        static let signInExpired = "Claude Code sign-in expired — run claude to refresh"
        static let signInRejected = "Claude Code sign-in was rejected — run claude to sign in again"
        static let unreachable = "Claude limits unreachable — showing the last known values"
        static let notUnderstood = "Claude limits response not understood"

        static func rateLimited(retryIn interval: TimeInterval) -> String {
            "Claude limits rate-limited — retrying in \(Int((interval / 60).rounded())) min"
        }

        static func httpError(_ code: Int) -> String {
            "Claude limits unavailable (HTTP \(code))"
        }
    }

    private let keychain: any KeychainReading
    private let transport: any HTTPTransport
    private let refreshInterval: TimeInterval
    private let maxBackoff: TimeInterval

    /// What the latest refresh produced; returned while the cache or a backoff holds.
    private var current: LimitSnapshot?
    /// The latest successful snapshot, whose rows failures keep showing.
    private var lastLive: LimitSnapshot?
    private var lastAttempt: Date?
    private var backoffInterval: TimeInterval?
    private var backoffUntil: Date?
    private var inFlight: Task<LimitSnapshot, Never>?

    init(
        keychain: any KeychainReading = SecurityKeychainReader(),
        transport: any HTTPTransport = URLSessionTransport(),
        refreshInterval: TimeInterval = defaultRefreshInterval,
        maxBackoff: TimeInterval = defaultMaxBackoff
    ) {
        self.keychain = keychain
        self.transport = transport
        self.refreshInterval = refreshInterval
        self.maxBackoff = maxBackoff
    }

    func limits(now: Date) async -> LimitSnapshot? {
        await limits(now: now, force: false)
    }

    /// - Parameter force: Skips the refresh-interval cache (e.g. when the panel opens), never a 429 backoff.
    func limits(now: Date, force: Bool) async -> LimitSnapshot? {
        if let inFlight { return await inFlight.value }
        if let backoffUntil, now < backoffUntil { return current }
        if !force, let lastAttempt, now.timeIntervalSince(lastAttempt) < refreshInterval { return current }

        lastAttempt = now
        let task = Task { await self.refresh(now: now) }
        inFlight = task
        let snapshot = await task.value
        inFlight = nil
        current = snapshot
        return snapshot
    }

    private func refresh(now: Date) async -> LimitSnapshot {
        let credentials: ClaudeCredentials
        do {
            guard let data = try keychain.genericPassword(service: Self.keychainService),
                  let parsed = ClaudeCredentials(data: data) else { return degraded(Status.signInNotFound, now: now) }
            credentials = parsed
        } catch KeychainError.status(errSecItemNotFound) {
            return degraded(Status.signInNotFound, now: now)
        } catch {
            return degraded(Status.keychainUnreadable, now: now)
        }
        guard !credentials.isExpired(now: now) else { return degraded(Status.signInExpired, now: now) }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: Self.request(token: credentials.accessToken))
        } catch {
            return degraded(Status.unreachable, now: now)
        }

        switch response.statusCode {
        case 200..<300:
            guard let usage = try? JSONDecoder().decode(ClaudeUsageResponse.self, from: data) else {
                return degraded(Status.notUnderstood, now: now)
            }
            backoffInterval = nil
            backoffUntil = nil
            let snapshot = LimitSnapshot(provider: .claude, rows: usage.rows(now: now), measuredAt: now)
            lastLive = snapshot
            return snapshot
        case 401, 403:
            return degraded(Status.signInRejected, now: now)
        case 429:
            let interval = min((backoffInterval ?? refreshInterval) * 2, maxBackoff)
            backoffInterval = interval
            backoffUntil = now.addingTimeInterval(interval)
            return degraded(Status.rateLimited(retryIn: interval), now: now)
        default:
            return degraded(Status.httpError(response.statusCode), now: now)
        }
    }

    /// The last known rows (or none) marked as not live, with `status` explaining why.
    private func degraded(_ status: String, now: Date) -> LimitSnapshot {
        LimitSnapshot(
            provider: .claude,
            rows: lastLive?.rows ?? [],
            measuredAt: lastLive?.measuredAt ?? now,
            status: status,
            limitsLive: false
        )
    }

    nonisolated static func request(token: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("burnbar-macos", forHTTPHeaderField: "User-Agent")
        return request
    }
}

/// The OAuth usage response, decoded leniently because its shape is not documented:
/// `{"five_hour": {"utilization": 0-100, "resets_at": ISO8601?}, "seven_day": …, …}`.
/// Unknown keys are ignored; a window that is null, malformed or lacks `utilization` is skipped.
nonisolated struct ClaudeUsageResponse: Decodable {
    struct Window: Hashable {
        let utilization: Double
        let resetsAt: Date?
    }

    /// Known windows in display order: response key, label, window minutes.
    static let layout: [(key: String, label: String, minutes: Int)] = [
        ("five_hour", LimitRow.label(windowMinutes: 300), 300),
        ("seven_day", LimitRow.label(windowMinutes: 10080), 10080),
        ("seven_day_opus", "Weekly Opus (7-day)", 10080),
        ("seven_day_sonnet", "Weekly Sonnet (7-day)", 10080),
    ]

    let windows: [String: Window]

    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    private struct RawWindow: Decodable {
        let utilization: Double?
        let resets_at: String?
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        var windows: [String: Window] = [:]
        for (key, _, _) in Self.layout {
            guard let raw = try? container.decode(RawWindow.self, forKey: Key(stringValue: key)),
                  let utilization = raw.utilization else { continue }
            windows[key] = Window(utilization: utilization, resetsAt: raw.resets_at.flatMap(TranscriptTimestamp.date(from:)))
        }
        self.windows = windows
    }

    /// One row per known window. A window without a reset has not started, so it resets one
    /// full window from `now`.
    func rows(now: Date) -> [LimitRow] {
        Self.layout.compactMap { key, label, minutes in
            guard let window = windows[key] else { return nil }
            let duration = TimeInterval(minutes) * 60
            return LimitRow(
                label: label,
                percent: window.utilization / 100,
                resetsAt: window.resetsAt ?? now.addingTimeInterval(duration),
                windowDuration: duration
            )
        }
    }
}
