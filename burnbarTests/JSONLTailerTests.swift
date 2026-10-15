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
}
