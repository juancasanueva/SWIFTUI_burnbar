//
//  KeychainReading.swift
//  burnbar
//

import Foundation
import Security

nonisolated enum KeychainError: Error, Equatable, Sendable {
    /// `SecItemCopyMatching` failed with this status (other than item-not-found).
    case status(OSStatus)
    /// The item exists but did not hold data.
    case unexpectedData
}

/// Reads generic-password items, e.g. the credentials Claude Code stores in the login Keychain.
nonisolated protocol KeychainReading: Sendable {
    /// The item's data, or nil when no item exists for `service`.
    func genericPassword(service: String) throws -> Data?
}

/// Reads the login Keychain through the Security framework. The first read of another app's
/// item may make macOS ask the user to allow access.
nonisolated struct SecurityKeychainReader: KeychainReading {
    func genericPassword(service: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw KeychainError.unexpectedData }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.status(status)
        }
    }
}

/// The OAuth credentials Claude Code keeps under the `Claude Code-credentials` Keychain item:
/// `{"claudeAiOauth":{"accessToken": String, "expiresAt": Int (ms)?, "subscriptionType": String?}}`.
nonisolated struct ClaudeCredentials: Hashable, Sendable {
    let accessToken: String
    let expiresAt: Date?
    let subscriptionType: String?

    private struct Item: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Double?
            let subscriptionType: String?
        }

        let claudeAiOauth: OAuth
    }

    /// Nil when `data` is not a credentials item or holds an empty token.
    init?(data: Data) {
        guard let oauth = try? JSONDecoder().decode(Item.self, from: data).claudeAiOauth,
              !oauth.accessToken.isEmpty else { return nil }
        accessToken = oauth.accessToken
        expiresAt = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        subscriptionType = oauth.subscriptionType
    }

    /// burnbar never refreshes the token itself; running `claude` does.
    func isExpired(now: Date) -> Bool {
        expiresAt.map { now >= $0 } ?? false
    }
}
