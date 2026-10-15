//
//  ClaudeLimitsFixtures.swift
//  burnbarTests
//
//  Synthetic Keychain and HTTP doubles for the Claude limits client; never real credentials.
//

import Foundation
import Synchronization
@testable import burnbar

struct StubKeychain: KeychainReading {
    var result: Result<Data?, KeychainError>

    init(_ result: Result<Data?, KeychainError>) { self.result = result }

    /// A credentials item holding `token`, expiring at `expiresAt` (omitted when nil).
    init(token: String = "test-token", expiresAt: Date? = nil, subscriptionType: String? = "max") {
        var oauth: [String: Any] = ["accessToken": token, "refreshToken": "synthetic-refresh"]
        if let expiresAt { oauth["expiresAt"] = Int(expiresAt.timeIntervalSince1970 * 1000) }
        if let subscriptionType { oauth["subscriptionType"] = subscriptionType }
        let data = try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": oauth])
        self.result = .success(data)
    }

    func genericPassword(service: String) throws -> Data? {
        try result.get()
    }
}

/// Counts reads of a credentials item and can hold each read until released, standing in for
/// a slow Keychain (a consent prompt or a locked keychain).
final class SlowKeychain: KeychainReading {
    private struct State {
        var data: Data
        var reads = 0
        var released = false
    }

    private let state: Mutex<State>
    private let gate = DispatchSemaphore(value: 0)
    private let holds: Bool

    /// - Parameter holds: When true, every read blocks until `release()` (or 5 s pass).
    init(token: String = "test-token", holds: Bool = false) {
        let data = try! JSONSerialization.data(withJSONObject: ["claudeAiOauth": ["accessToken": token]])
        state = Mutex(State(data: data))
        self.holds = holds
    }

    var reads: Int { state.withLock { $0.reads } }
    var released: Bool { state.withLock { $0.released } }

    func release() {
        state.withLock { $0.released = true }
        gate.signal()
    }

    func genericPassword(service: String) throws -> Data? {
        let data = state.withLock { state in
            state.reads += 1
            return state.data
        }
        if holds { _ = gate.wait(timeout: .now() + 5) }
        return data
    }
}

/// Replays canned responses in order and records every request it was sent.
///
/// A Mutex-backed class rather than an actor: in this target an actor conforming to the
/// app's `nonisolated` protocol trips a compiler diagnostic.
final class StubTransport: HTTPTransport {
    enum Reply: Sendable {
        case status(Int, String)
        case headers(Int, String, [String: String])
        case failure(URLError.Code)
    }

    private struct State {
        var replies: [Reply]
        var requests: [URLRequest] = []
    }

    private let state: Mutex<State>
    private let delay: Duration

    /// - Parameter delay: How long each reply takes, so calls can overlap.
    init(_ replies: [Reply], delay: Duration = .zero) {
        state = Mutex(State(replies: replies))
        self.delay = delay
    }

    /// Async so call sites read like the transport they stand in for.
    var requests: [URLRequest] {
        get async { state.withLock { $0.requests } }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply? = state.withLock { state in
            state.requests.append(request)
            return state.replies.isEmpty ? nil : state.replies.removeFirst()
        }
        if delay > .zero { try await Task.sleep(for: delay) }
        switch reply {
        case nil:
            throw URLError(.notConnectedToInternet)
        case .status(let code, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: nil)!
            return (Data(body.utf8), response)
        case .headers(let code, let body, let fields):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: "HTTP/1.1", headerFields: fields)!
            return (Data(body.utf8), response)
        case .failure(let code):
            throw URLError(code)
        }
    }
}

/// An OAuth usage body; nil windows are written as JSON null.
func usageBody(fiveHour: String? = nil, sevenDay: String? = nil, opus: String? = nil, sonnet: String? = nil) -> String {
    let parts = [("five_hour", fiveHour), ("seven_day", sevenDay), ("seven_day_opus", opus), ("seven_day_sonnet", sonnet)]
    return "{" + parts.map { #""\#($0.0)":\#($0.1 ?? "null")"# }.joined(separator: ",") + "}"
}

func usageWindow(_ utilization: Double, resetsAt: String?) -> String {
    let reset = resetsAt.map { #""\#($0)""# } ?? "null"
    return #"{"utilization":\#(utilization),"resets_at":\#(reset)}"#
}
