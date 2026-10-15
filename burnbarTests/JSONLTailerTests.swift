//
//  JSONLTailerTests.swift
//  burnbarTests
//

import Foundation
import Testing
@testable import burnbar

final class JSONLTailerTests {
    private let root: URL

    init() throws {
        root = try makeTemporaryDirectory()
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func file(_ path: String) -> URL { root.appending(path: path) }

    /// Reads `url` once through `tailer`, returning the lines and whether a rewrite was reported.
    private func read(_ url: URL, with tailer: inout JSONLTailer) throws -> (lines: [String], rewritten: Bool) {
        let entry = try #require(JSONLTailer.scan(root: root) { $0 == url.standardizedFileURL }.first)
        var lines: [String] = []
        var rewritten = false
        tailer.read(entry, rewritten: { rewritten = true }, line: { lines.append(String(decoding: $0, as: UTF8.self)) })
        return (lines, rewritten)
    }

    @Test func scanFindsMatchingFilesRecursively() throws {
        try writeLines(["{}"], to: file("a/one.jsonl"))
        try writeLines(["{}"], to: file("a/b/two.jsonl"))
        try writeLines(["{}"], to: file("a/three.txt"))

        let names = JSONLTailer.scan(root: root) { $0.pathExtension == "jsonl" }.map(\.url.lastPathComponent).sorted()
        #expect(names == ["one.jsonl", "two.jsonl"])
        #expect(JSONLTailer.scan(root: root.appending(path: "missing")) { _ in true }.isEmpty)
    }

    @Test func readsLinesAcrossSmallChunks() throws {
        let url = file("s.jsonl")
        let lines = (0..<20).map { #"{"n":\#($0),"pad":"\#(String(repeating: "x", count: $0 * 3))"}"# }
        try writeLines(lines, to: url)
        var tailer = JSONLTailer(chunkSize: 7)

        let first = try read(url, with: &tailer)
        #expect(first.lines == lines)
        #expect(first.rewritten == false)
        #expect(try read(url, with: &tailer).lines.isEmpty)
    }

    @Test func holdsBackAPartialTrailingLine() throws {
        let url = file("s.jsonl")
        try writeLines(["one"], to: url)
        try appendText("tw", to: url)
        var tailer = JSONLTailer(chunkSize: 2)
        #expect(try read(url, with: &tailer).lines == ["one"])

        try appendText("o\nthree\n", to: url)
        #expect(try read(url, with: &tailer).lines == ["two", "three"])
    }

    @Test func skipsEmptyLines() throws {
        let url = file("s.jsonl")
        try writeLines(["a", "", "b"], to: url)
        var tailer = JSONLTailer()
        #expect(try read(url, with: &tailer).lines == ["a", "b"])
    }

    @Test func reportsAnInPlaceRewriteThatKeptGrowing() throws {
        let url = file("s.jsonl")
        try writeLines(["alpha"], to: url)
        var tailer = JSONLTailer()
        _ = try read(url, with: &tailer)

        try writeLines(["bravo-longer", "charlie"], to: url)
        let second = try read(url, with: &tailer)
        #expect(second.rewritten)
        #expect(second.lines == ["bravo-longer", "charlie"])
    }

    @Test func doesNotReportAppendsAsRewrites() throws {
        let url = file("s.jsonl")
        try writeLines(["alpha"], to: url)
        var tailer = JSONLTailer()
        _ = try read(url, with: &tailer)

        try appendText("bravo\n", to: url)
        let second = try read(url, with: &tailer)
        #expect(second.rewritten == false)
        #expect(second.lines == ["bravo"])
    }

    @Test func retainForgetsVanishedFiles() throws {
        let url = file("s.jsonl")
        try writeLines(["alpha"], to: url)
        var tailer = JSONLTailer()
        _ = try read(url, with: &tailer)
        #expect(tailer.isTracked(url.standardizedFileURL))

        #expect(tailer.retain([]) == [url.standardizedFileURL])
        #expect(tailer.isTracked(url.standardizedFileURL) == false)
    }

    private func lastLines(of url: URL, maxBytes: Int) -> [String] {
        var lines: [String] = []
        JSONLTailer.lastLines(of: url, maxBytes: maxBytes) { lines.append(String(decoding: $0, as: UTF8.self)) }
        return lines
    }

    @Test func lastLinesReadsAWholeFileSmallerThanTheRange() throws {
        let url = file("s.jsonl")
        try writeLines(["one", "", "two"], to: url)
        #expect(lastLines(of: url, maxBytes: 1024) == ["one", "two"])
    }

    @Test func lastLinesSkipsALineCutByTheStartOfTheRange() throws {
        let url = file("s.jsonl")
        try writeLines(["first-line", "second", "third"], to: url)
        // The last 17 bytes are "ine\nsecond\nthird\n": "ine" is a cut remnant of "first-line".
        #expect(lastLines(of: url, maxBytes: 17) == ["second", "third"])
        // A range starting exactly after a newline still drops its first line: the cut is not detectable.
        #expect(lastLines(of: url, maxBytes: 13) == ["third"])
    }

    @Test func lastLinesYieldsNothingWhenTheRangeHoldsNoNewline() throws {
        let url = file("s.jsonl")
        try writeLines(["a-very-long-single-line"], to: url, terminated: false)
        #expect(lastLines(of: url, maxBytes: 5).isEmpty)
        #expect(lastLines(of: file("missing.jsonl"), maxBytes: 5).isEmpty)
        #expect(lastLines(of: url, maxBytes: 0).isEmpty)
    }

    /// The probed file is not being appended to (it is older than the burn window), so its
    /// last line is complete even without a newline; a torn line just fails to decode later.
    @Test func lastLinesIncludesATrailingLineWithoutNewline() throws {
        let url = file("s.jsonl")
        try writeLines(["one", "two"], to: url, terminated: false)
        #expect(lastLines(of: url, maxBytes: 1024) == ["one", "two"])
        #expect(lastLines(of: url, maxBytes: 6) == ["two"])
    }
}
