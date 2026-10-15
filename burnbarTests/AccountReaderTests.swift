//
//  AccountReaderTests.swift
//  burnbarTests
//
//  Synthetic account files in a temporary home; never the real ~/.claude.json or ~/.codex/auth.json.
//

import Foundation
import Testing
@testable import burnbar

final class AccountReaderTests {
    private let home: URL

    init() throws {
        home = try makeTemporaryDirectory()
    }

    deinit {
        try? FileManager.default.removeItem(at: home)
    }

    private var reader: AccountReader { AccountReader(home: home) }

    private func write(_ text: String, to path: String) throws {
        try writeLines([text], to: home.appending(path: path))
    }

    /// An unsigned JWT whose payload is `payload`, base64url-encoded without padding.
    private func jwt(_ payload: String) -> String {
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJub25lIn0.\(encoded).signature"
    }

    // MARK: Claude

    @Test func readsTheClaudeOAuthAccount() throws {
        try write(#"{"numStartups":3,"oauthAccount":{"accountUuid":"u","emailAddress":"ada@example.com","displayName":"Ada","organizationName":"Analytical Engines"},"projects":{}}"#, to: ".claude.json")
        let account = try #require(reader.claude())
        #expect(account == AccountInfo(email: "ada@example.com", name: "Ada", organization: "Analytical Engines"))
        #expect(account.label == "ada@example.com")
    }

    @Test func claudeAccountIsNilWhenMissingOrEmpty() throws {
        #expect(reader.claude() == nil)
        try write(#"{"numStartups":3}"#, to: ".claude.json")
        #expect(reader.claude() == nil)
        try write(#"{"oauthAccount":{"emailAddress":"","displayName":""}}"#, to: ".claude.json")
        #expect(reader.claude() == nil)
        try write("not json", to: ".claude.json")
        #expect(reader.claude() == nil)
    }

    @Test func claudeLabelFallsBackToTheName() throws {
        try write(#"{"oauthAccount":{"displayName":"Ada"}}"#, to: ".claude.json")
        #expect(reader.claude()?.label == "Ada")
    }

    // MARK: Codex

    @Test func readsTheCodexIDTokenPayload() throws {
        // "é" and "?" make the base64 alphabet use "-"/"_" and need padding restored.
        let token = jwt(#"{"email":"grace@example.com","name":"Grace Hopperé?","exp":1}"#)
        try write(#"{"OPENAI_API_KEY":null,"tokens":{"id_token":"\#(token)","access_token":"a","refresh_token":"r"}}"#, to: ".codex/auth.json")
        let account = try #require(reader.codex())
        #expect(account.email == "grace@example.com")
        #expect(account.name == "Grace Hopperé?")
        #expect(account.label == "grace@example.com")
    }

    @Test func codexWithAnAPIKeyIsLabelledAPIKey() throws {
        try write(#"{"OPENAI_API_KEY":"sk-synthetic"}"#, to: ".codex/auth.json")
        #expect(reader.codex() == .apiKey)
        #expect(reader.codex()?.label == "API key")
    }

    @Test func codexAccountIsNilWhenMissingOrUnreadable() throws {
        #expect(reader.codex() == nil)
        try write(#"{"OPENAI_API_KEY":null,"tokens":null}"#, to: ".codex/auth.json")
        #expect(reader.codex() == nil)
        try write(#"{"tokens":{"id_token":"not-a-jwt"}}"#, to: ".codex/auth.json")
        #expect(reader.codex() == nil)
        try write(#"{"tokens":{"id_token":"\#(jwt(#"{"sub":"x"}"#))"}}"#, to: ".codex/auth.json")
        #expect(reader.codex() == nil)
    }
}
