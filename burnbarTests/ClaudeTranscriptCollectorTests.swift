//
//  ClaudeTranscriptCollectorTests.swift
//  burnbarTests
//

import Foundation
import Testing
@testable import burnbar

/// Runs against real temporary files, so `clock` follows wall time to match file modification dates.
final class ClaudeTranscriptCollectorTests {
    private let root: URL
    private let clock = Date()

    init() throws {
        root = try makeTemporaryDirectory()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ path: String) -> URL { root.appending(path: path) }

    private func collector() -> ClaudeTranscriptCollector { ClaudeTranscriptCollector(root: root) }

    @Test func readsNestedTranscripts() async throws {
        try writeLines([claudeLine(id: "a", at: clock.addingTimeInterval(-60))], to: file("proj-1/s1.jsonl"))
        try writeLines([claudeLine(id: "b", at: clock.addingTimeInterval(-30))], to: file("proj-2/s2/subagents/agent.jsonl"))
        try writeLines([claudeLine(id: "c", at: clock)], to: file("proj-1/notes.txt"))

        let events = await collector().events(now: clock)
        #expect(events.map(\.split.input) == [10, 10])
        #expect(events.map(\.timestamp) == events.map(\.timestamp).sorted())
    }

    @Test func picksUpAppendedLinesIncrementally() async throws {
        let url = file("p/s.jsonl")
        try writeLines([claudeLine(id: "a", at: clock.addingTimeInterval(-120))], to: url)
        let sut = collector()
        #expect(await sut.events(now: clock).count == 1)

        try appendText(claudeLine(id: "b", at: clock.addingTimeInterval(-60)) + "\n", to: url)
        #expect(await sut.events(now: clock).count == 2)
        #expect(await sut.events(now: clock).count == 2)
    }

    @Test func waitsForPartialTrailingLine() async throws {
        let url = file("p/s.jsonl")
        try writeLines([claudeLine(id: "a", at: clock.addingTimeInterval(-120))], to: url)
        let sut = collector()
        #expect(await sut.events(now: clock).count == 1)

        let next = claudeLine(id: "b", at: clock.addingTimeInterval(-60), output: 77)
        let cut = next.index(next.startIndex, offsetBy: next.count / 2)
        try appendText(String(next[..<cut]), to: url)
        #expect(await sut.events(now: clock).count == 1)

        try appendText(String(next[cut...]) + "\n", to: url)
        let events = await sut.events(now: clock)
        #expect(events.count == 2)
        #expect(events.last?.split.output == 77)
    }

    @Test func dedupesRevisionsAcrossReads() async throws {
        let url = file("p/s.jsonl")
        let at = clock.addingTimeInterval(-60)
        try writeLines([claudeLine(id: "a", at: at, output: 5)], to: url)
        let sut = collector()
        _ = await sut.events(now: clock)

        try appendText(claudeLine(id: "a", at: at, output: 50) + "\n" + claudeLine(id: "a", at: at, output: 20) + "\n", to: url)
        let events = await sut.events(now: clock)
        #expect(events.count == 1)
        #expect(events.first?.split.output == 50)
    }

    @Test func rereadsAFileThatShrank() async throws {
        let url = file("p/s.jsonl")
        try writeLines([
            claudeLine(id: "a", at: clock.addingTimeInterval(-90)),
            claudeLine(id: "b", at: clock.addingTimeInterval(-80)),
        ], to: url)
        let sut = collector()
        #expect(await sut.events(now: clock).count == 2)

        try writeLines([claudeLine(id: "c", at: clock.addingTimeInterval(-10), output: 9)], to: url)
        let events = await sut.events(now: clock)
        #expect(events.contains { $0.split.output == 9 })
    }

    @Test func dropsAndPrunesEventsOutsideTheWindow() async throws {
        let url = file("p/s.jsonl")
        try writeLines([
            claudeLine(id: "old", at: clock.addingTimeInterval(-7 * hour)),
            claudeLine(id: "edge", at: clock.addingTimeInterval(-5 * hour)),
            claudeLine(id: "new", at: clock.addingTimeInterval(-60)),
        ], to: url)
        let sut = collector()
        #expect(await sut.events(now: clock).count == 2)

        // Two hours later "edge" is 7 h old and falls out of the 6 h window plus margin.
        #expect(await sut.events(now: clock.addingTimeInterval(2 * hour)).count == 1)
    }

    @Test func skipsFilesModifiedBeforeTheWindow() async throws {
        let url = file("p/stale.jsonl")
        try writeLines([claudeLine(id: "a", at: clock.addingTimeInterval(-60))], to: url)
        try FileManager.default.setAttributes([.modificationDate: clock.addingTimeInterval(-8 * hour)], ofItemAtPath: url.path)

        #expect(await collector().events(now: clock).isEmpty)
    }

    @Test func usesFileNameWhenLinesHaveNoSessionID() async throws {
        try writeLines([claudeLine(id: "a", at: clock.addingTimeInterval(-60), sessionID: nil)], to: file("p/1234-abcd.jsonl"))
        #expect(await collector().events(now: clock).first?.sessionID == "1234-abcd")
    }

    @Test func missingRootYieldsNoEvents() async {
        let sut = ClaudeTranscriptCollector(root: root.appending(path: "missing"))
        #expect(await sut.events(now: clock).isEmpty)
    }
}
