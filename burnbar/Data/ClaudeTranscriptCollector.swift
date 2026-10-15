//
//  ClaudeTranscriptCollector.swift
//  burnbar
//

import Foundation

/// Incrementally collects Claude turns from `~/.claude/projects/**/*.jsonl`.
///
/// Each call scans the tree, reads only bytes appended since the last read (a trailing line
/// without a newline waits for the next call), re-reads a file from the start when it shrank,
/// dedupes by message id and prunes turns older than the window plus a margin to bound memory.
/// Files not yet tracked are skipped when last modified before that cutoff: they cannot hold
/// turns inside the window.
actor ClaudeTranscriptCollector: UsageCollector {
    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".claude/projects", directoryHint: .isDirectory)

    private nonisolated struct FileState {
        var offset: UInt64
        var size: UInt64
        var modified: Date
    }

    private let root: URL
    private let retention: TimeInterval
    private var files: [URL: FileState] = [:]
    private var turns: [String: ClaudeTurn] = [:]

    /// - Parameters:
    ///   - window: Trailing window the app displays (360 min).
    ///   - margin: Extra history kept past the window so a late refresh never loses an edge turn.
    init(root: URL = defaultRoot, window: TimeInterval = 360 * 60, margin: TimeInterval = 30 * 60) {
        self.root = root
        self.retention = window + margin
    }

    func events(now: Date) -> [UsageEvent] {
        let cutoff = now.addingTimeInterval(-retention)
        var seen = Set<URL>()
        for (url, size, modified) in transcripts() {
            seen.insert(url)
            read(url, size: size, modified: modified, cutoff: cutoff)
        }
        files = files.filter { seen.contains($0.key) }
        turns = turns.filter { $0.value.event.timestamp >= cutoff }
        return turns.values.map(\.event).sorted { $0.timestamp < $1.timestamp }
    }

    private func transcripts() -> [(URL, UInt64, Date)] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var found: [(URL, UInt64, Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let size = values.fileSize, let modified = values.contentModificationDate else { continue }
            found.append((url.standardizedFileURL, UInt64(size), modified))
        }
        return found
    }

    private func read(_ url: URL, size: UInt64, modified: Date, cutoff: Date) {
        var state: FileState
        if let known = files[url] {
            if known.size == size && known.modified == modified { return }
            state = known
            if size < state.offset { state.offset = 0 }   // truncated or rewritten
        } else {
            guard modified >= cutoff else { return }
            state = FileState(offset: 0, size: 0, modified: modified)
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: state.offset)) != nil,
              let chunk = try? handle.readToEnd() else { return }

        let consumed = ingest(chunk, sessionID: url.deletingPathExtension().lastPathComponent, cutoff: cutoff)
        state.offset += UInt64(consumed)
        state.size = size
        state.modified = modified
        files[url] = state
    }

    /// Parses every complete line of `chunk`; returns the bytes consumed, up to the last newline.
    private func ingest(_ chunk: Data, sessionID: String, cutoff: Date) -> Int {
        guard let lastNewline = chunk.lastIndex(of: 0x0A) else { return 0 }
        var start = chunk.startIndex
        while start <= lastNewline, let end = chunk[start...lastNewline].firstIndex(of: 0x0A) {
            if end > start,
               let turn = ClaudeTranscriptParser.turn(from: chunk[start..<end], fallbackSessionID: sessionID),
               turn.event.timestamp >= cutoff {
                ClaudeTranscriptParser.merge(turn, into: &turns)
            }
            start = end + 1
        }
        return lastNewline - chunk.startIndex + 1
    }
}
