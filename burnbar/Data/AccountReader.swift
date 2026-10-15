//
//  AccountReader.swift
//  burnbar
//

import Foundation

/// Which account each provider's CLI is signed in as; injectable for tests.
nonisolated protocol AccountReading: Sendable {
    func claude() -> AccountInfo?
    func codex() -> AccountInfo?
}

/// Reads which account each provider's CLI is signed in as, from its local config files.
///
/// - Claude: `~/.claude.json` → `oauthAccount.{emailAddress, displayName, organizationName}`.
/// - Codex: `~/.codex/auth.json` → the `tokens.id_token` JWT payload's `email`/`name` (decoded,
///   not verified; it is only a label), else `AccountInfo.apiKey` when `OPENAI_API_KEY` is set.
///
/// Only these fields are decoded; tokens are never kept or logged.
nonisolated struct AccountReader: AccountReading {
    let home: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    func claude() -> AccountInfo? {
        struct Config: Decodable {
            struct OAuthAccount: Decodable {
                let emailAddress: String?
                let displayName: String?
                let organizationName: String?
            }

            let oauthAccount: OAuthAccount?
        }

        guard let account = decode(Config.self, at: ".claude.json")?.oauthAccount else { return nil }
        return Self.account(email: account.emailAddress, name: account.displayName, organization: account.organizationName)
    }

    func codex() -> AccountInfo? {
        struct Auth: Decodable {
            struct Tokens: Decodable {
                let id_token: String?
            }

            let OPENAI_API_KEY: String?
            let tokens: Tokens?
        }

        struct Claims: Decodable {
            let email: String?
            let name: String?
        }

        guard let auth = decode(Auth.self, at: ".codex/auth.json") else { return nil }
        if let token = auth.tokens?.id_token,
           let payload = Self.jwtPayload(token),
           let claims = try? JSONDecoder().decode(Claims.self, from: payload),
           let account = Self.account(email: claims.email, name: claims.name, organization: nil) {
            return account
        }
        if let key = auth.OPENAI_API_KEY, !key.isEmpty { return .apiKey }
        return nil
    }

    private func decode<T: Decodable>(_ type: T.Type, at path: String) -> T? {
        guard let data = try? Data(contentsOf: home.appending(path: path)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Nil when every field is missing or empty.
    private static func account(email: String?, name: String?, organization: String?) -> AccountInfo? {
        func nonEmpty(_ text: String?) -> String? { text.flatMap { $0.isEmpty ? nil : $0 } }
        let account = AccountInfo(email: nonEmpty(email), name: nonEmpty(name), organization: nonEmpty(organization))
        return account.label == nil ? nil : account
    }

    /// The base64url-decoded middle segment of a JWT.
    static func jwtPayload(_ token: String) -> Data? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3 else { return nil }
        var base64 = segments[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
