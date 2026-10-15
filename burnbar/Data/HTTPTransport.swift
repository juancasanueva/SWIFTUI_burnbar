//
//  HTTPTransport.swift
//  burnbar
//

import Foundation

/// Sends one HTTP request; injectable so API clients are tested without a network.
nonisolated protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// `URLSession`-backed transport. Ephemeral by default: no cookies, cache or credential storage.
nonisolated struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    init(session: URLSession = URLSession(configuration: .ephemeral)) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}
