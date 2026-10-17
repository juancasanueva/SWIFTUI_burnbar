//
//  ClaudeLimitsClient.swift
//  burnbar
//

import Foundation

/// Fetches Claude plan limits from the OAuth usage endpoint with Claude Code's own sign-in.
///
/// The access token comes from the `Claude Code-credentials` Keychain item; burnbar never
/// refreshes it (an expired token asks the user to run `claude`). The Keychain is read off the
/// actor (the first read may show a consent prompt) and the token is kept in memory until it
/// expires or is rejected; after a failed read only a forced refresh tries again, so a denied
/// prompt is not repeated every interval. Results are cached for `refreshInterval` unless a
/// refresh is forced. HTTP 429 backs off by doubling the interval up to `maxBackoff`, or longer
/// when `Retry-After` asks for it (still capped), and even a forced refresh waits it out.
/// Every failure keeps the last known rows (with their original `measuredAt`) and explains
/// itself in `LimitSnapshot.status`. Before any live reading this launch, the last known rows are
/// the newest persisted samples of windows that have not reset yet (see `lastPersisted(now:)`).
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
    /// Persisted readings from earlier launches; the fallback until a live reading arrives.
    private let samples: (any LimitSampleRecording)?

    /// What the latest refresh produced; returned while the cache or a backoff holds.
    private var current: LimitSnapshot?
    /// The latest successful snapshot, whose rows failures keep showing.
    private var lastLive: LimitSnapshot?
    /// Set by a missing or rejected sign-in: persisted samples may belong to another account
    /// until a live reading confirms the current one.
    private var persistedUntrusted = false
    private var lastAttempt: Date?
    private var backoffInterval: TimeInterval?
    private var backoffUntil: Date?
    private var inFlight: Task<LimitSnapshot, Never>?
    /// The token in use; dropped when it expires or the endpoint rejects it.
    private var cachedCredentials: ClaudeCredentials?
    /// Set after a Keychain read failed (other than not-found); only a forced refresh retries.
    private var keychainFailed = false

    private enum CredentialsLookup {
        case found(ClaudeCredentials)
        case failed(String)
        /// No sign-in at all: whatever was known may belong to another account.
        case signedOut(String)
    }

    init(
        keychain: any KeychainReading = SecurityKeychainReader(),
        transport: any HTTPTransport = URLSessionTransport(),
        refreshInterval: TimeInterval = defaultRefreshInterval,
        maxBackoff: TimeInterval = defaultMaxBackoff,
        samples: (any LimitSampleRecording)? = nil
    ) {
        self.samples = samples
        self.keychain = keychain
        self.transport = transport
        self.refreshInterval = refreshInterval
        self.maxBackoff = maxBackoff
    }

    func limits(now: Date) async -> LimitSnapshot? {
        await limits(now: now, force: false)
    }

    /// Whether a refresh is under way.
    var isRefreshing: Bool { inFlight != nil }

    /// - Parameter force: Skips the refresh-interval cache (e.g. when the panel opens), never a 429 backoff.
    func limits(now: Date, force: Bool) async -> LimitSnapshot? {
        if let inFlight { return await inFlight.value }
        if let backoffUntil, now < backoffUntil { return current }
        if !force, let lastAttempt, now.timeIntervalSince(lastAttempt) < refreshInterval { return current }

        lastAttempt = now
        let task = Task { await self.refresh(now: now, force: force) }
        inFlight = task
        let snapshot = await task.value
        inFlight = nil
        current = snapshot
        return snapshot
    }

    private func refresh(now: Date, force: Bool) async -> LimitSnapshot {
        let credentials: ClaudeCredentials
        switch await lookUpCredentials(now: now, force: force) {
        case .found(let found): credentials = found
        case .failed(let status): return await degraded(status, now: now)
        case .signedOut(let status): return signedOut(status, now: now)
        }

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: Self.request(token: credentials.accessToken))
        } catch {
            return await degraded(Status.unreachable, now: now)
        }

        switch response.statusCode {
        case 200..<300:
            guard let usage = try? JSONDecoder().decode(ClaudeUsageResponse.self, from: data) else {
                return await degraded(Status.notUnderstood, now: now)
            }
            backoffInterval = nil
            backoffUntil = nil
            let snapshot = LimitSnapshot(provider: .claude, rows: usage.rows(now: now), measuredAt: now)
            lastLive = snapshot
            persistedUntrusted = false
            return snapshot
        case 401, 403:
            cachedCredentials = nil
            return signedOut(Status.signInRejected, now: now)
        case 429:
            let local = min((backoffInterval ?? refreshInterval) * 2, maxBackoff)
            backoffInterval = local
            let requested = response.value(forHTTPHeaderField: "Retry-After").flatMap { Self.retryAfter($0, now: now) } ?? 0
            let wait = min(max(local, requested), maxBackoff)
            backoffUntil = now.addingTimeInterval(wait)
            return await degraded(Status.rateLimited(retryIn: wait), now: now)
        default:
            return await degraded(Status.httpError(response.statusCode), now: now)
        }
    }

    /// The cached token while valid, else a fresh Keychain read.
    private func lookUpCredentials(now: Date, force: Bool) async -> CredentialsLookup {
        if let cachedCredentials, !cachedCredentials.isExpired(now: now) { return .found(cachedCredentials) }
        cachedCredentials = nil
        if keychainFailed && !force { return .failed(Status.keychainUnreadable) }

        let data: Data?
        do {
            data = try await Self.readKeychain(keychain, service: Self.keychainService)
            keychainFailed = false
        } catch KeychainError.status(errSecItemNotFound) {
            keychainFailed = false
            return .signedOut(Status.signInNotFound)
        } catch {
            keychainFailed = true
            return .failed(Status.keychainUnreadable)
        }
        guard let data, let parsed = ClaudeCredentials(data: data) else { return .signedOut(Status.signInNotFound) }
        guard !parsed.isExpired(now: now) else { return .failed(Status.signInExpired) }
        cachedCredentials = parsed
        return .found(parsed)
    }

    /// `SecItemCopyMatching` blocks (e.g. on a consent prompt), so it runs off the actor.
    @concurrent
    private nonisolated static func readKeychain(_ keychain: any KeychainReading, service: String) async throws -> Data? {
        try keychain.genericPassword(service: service)
    }

    /// Seconds to wait from a `Retry-After` value: delta-seconds or an HTTP-date. Nil when
    /// unparseable or negative.
    nonisolated static func retryAfter(_ value: String, now: Date) -> TimeInterval? {
        let text = value.trimmingCharacters(in: .whitespaces)
        if let seconds = Int(text) { return seconds >= 0 ? TimeInterval(seconds) : nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        guard let date = formatter.date(from: text) else { return nil }
        return max(0, date.timeIntervalSince(now))
    }

    /// No rows: a missing or rejected sign-in may mean another account, so neither the last live
    /// reading nor the persisted samples are shown, and the last live reading is forgotten.
    private func signedOut(_ status: String, now: Date) -> LimitSnapshot {
        lastLive = nil
        persistedUntrusted = true
        return LimitSnapshot(provider: .claude, rows: [], measuredAt: now, status: status, limitsLive: false)
    }

    /// The last known rows (or none) marked as not live, with `status` explaining why. Used for
    /// transient failures (rate limits, network, server errors) with the same sign-in.
    private func degraded(_ status: String, now: Date) async -> LimitSnapshot {
        let known = if let lastLive { lastLive } else { await lastPersisted(now: now) }
        return LimitSnapshot(
            provider: .claude,
            rows: known?.rows ?? [],
            measuredAt: known?.measuredAt ?? now,
            status: status,
            limitsLive: false
        )
    }

    /// The newest persisted sample of each known window whose reported reset is still ahead,
    /// measured at the oldest of those samples so no row looks fresher than it is; nil when there is none. Window lengths come from
    /// `ClaudeUsageResponse.layout`; samples without a reported reset cannot be placed and are skipped.
    private func lastPersisted(now: Date) async -> LimitSnapshot? {
        guard let samples, !persistedUntrusted else { return nil }
        var rows: [LimitRow] = []
        var measuredAt: Date?
        for (_, label, minutes) in ClaudeUsageResponse.layout {
            guard let sample = await samples.samples(provider: .claude, label: label).last,
                  let resetsAt = sample.resetsAt, resetsAt > now else { continue }
            rows.append(LimitRow(label: label, percent: sample.percent, resetsAt: resetsAt,
                                 windowDuration: TimeInterval(minutes) * 60))
            measuredAt = min(measuredAt ?? sample.t, sample.t)
        }
        guard let measuredAt else { return nil }
        return LimitSnapshot(provider: .claude, rows: rows, measuredAt: measuredAt, limitsLive: false)
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
