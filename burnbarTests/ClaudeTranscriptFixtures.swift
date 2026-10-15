//
//  ClaudeTranscriptFixtures.swift
//  burnbarTests
//
//  Synthetic Claude transcript lines; never real transcript content.
//

import Foundation
@testable import burnbar

func claudeTimestamp(_ date: Date) -> String {
    date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
}

/// One assistant line in the Claude Code transcript shape.
func claudeLine(
    id: String,
    at date: Date,
    model: String = "claude-opus-4",
    input: Int = 10,
    cacheWrite: Int = 0,
    output: Int = 5,
    cacheRead: Int = 0,
    sessionID: String? = "session-a"
) -> String {
    let session = sessionID.map { #","sessionId":"\#($0)""# } ?? ""
    return #"{"type":"assistant","timestamp":"\#(claudeTimestamp(date))"\#(session),"#
        + #""message":{"id":"\#(id)","model":"\#(model)","role":"assistant","content":[{"type":"text","text":"hi"}],"#
        + #""usage":{"input_tokens":\#(input),"cache_creation_input_tokens":\#(cacheWrite),"#
        + #""output_tokens":\#(output),"cache_read_input_tokens":\#(cacheRead),"service_tier":"standard"}}}"#
}

/// A fresh, empty directory under the temporary directory.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "burnbar-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func writeLines(_ lines: [String], to url: URL, terminated: Bool = true) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let text = lines.joined(separator: "\n") + (terminated && !lines.isEmpty ? "\n" : "")
    try Data(text.utf8).write(to: url)
}

func appendText(_ text: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(text.utf8))
}
