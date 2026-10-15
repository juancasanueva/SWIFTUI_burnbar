//
//  ClaudeTranscriptCollector.swift
//  burnbar
//

import Foundation

/// Incrementally collects Claude turns from `~/.claude/projects/**/*.jsonl`.
///
/// Each call scans the tree and reads only bytes appended since the last read through a
/// `JSONLTailer` (a trailing line without a newline waits for the next call). Turns are kept
/// per file: when a file is rewritten (shrunk, replaced or changed in place) its previous turns
/// are dropped and its new content ingested from the start, and a deleted file's turns are
/// dropped. Turns are deduplicated by message id across files and pruned when older than the
/// window plus a margin to bound memory. Files not yet tracked are skipped when last modified
/// before that cutoff: they cannot hold turns inside the window.
actor ClaudeTranscriptCollector: UsageCollector {
    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/projects", directoryHint: .isDirectory)

    private let root: URL
    private let retention: TimeInterval
    private var tailer: JSONLTailer
    /// Deduplicated turns of each file, keyed by message id.
    private var turnsByFile: [URL: [String: ClaudeTurn]] = [:]

    /// - Parameters:
    ///   - window: Trailing window the app displays (360 min).
    ///   - margin: Extra history kept past the window so a late refresh never loses an edge turn.
    init(
        root: URL = defaultRoot,
        window: TimeInterval = 360 * 60,
        margin: TimeInterval = 30 * 60,
        chunkSize: Int = JSONLTailer.defaultChunkSize
    ) {
        self.root = root
        self.retention = window + margin
        self.tailer = JSONLTailer(chunkSize: chunkSize)
    }

    func events(now: Date) -> [UsageEvent] {
        let cutoff = now.addingTimeInterval(-retention)
        let found = JSONLTailer.scan(root: root) { $0.pathExtension == "jsonl" }
        for file in found where tailer.isTracked(file.url) || file.modified >= cutoff {
            read(file, cutoff: cutoff)
        }
        for url in tailer.retain(Set(found.map(\.url))) { turnsByFile[url] = nil }

        var merged: [String: ClaudeTurn] = [:]
        for (url, turns) in turnsByFile {
            let kept = turns.filter { $0.value.event.timestamp >= cutoff }
            turnsByFile[url] = kept
            for turn in kept.values { ClaudeTranscriptParser.merge(turn, into: &merged) }
        }
        return merged.values.map(\.event).sorted { $0.timestamp < $1.timestamp }
    }

    private func read(_ file: JSONLFile, cutoff: Date) {
        let sessionID = file.url.deletingPathExtension().lastPathComponent
        var turns = turnsByFile[file.url] ?? [:]
        tailer.read(file, rewritten: { turns = [:] }, line: { line in
            if let turn = ClaudeTranscriptParser.turn(from: line, fallbackSessionID: sessionID),
               turn.event.timestamp >= cutoff {
                ClaudeTranscriptParser.merge(turn, into: &turns)
            }
        })
        turnsByFile[file.url] = turns
    }
}
