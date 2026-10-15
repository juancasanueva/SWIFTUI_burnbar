//
//  JSONLTailer.swift
//  burnbar
//

import Foundation

/// A JSONL file found by `JSONLTailer.scan`.
nonisolated struct JSONLFile: Hashable, Sendable {
    let url: URL
    let size: UInt64
    let modified: Date
}

/// Incremental reader for append-only JSONL files, shared by the transcript collectors.
///
/// Per file it remembers how far it read, so each `read` only delivers lines appended since.
/// A trailing line without a newline is held back until it is complete. Reads happen in
/// bounded chunks, so memory stays at about one chunk plus the longest line.
///
/// A file counts as rewritten, and is read again from the start, when it shrank below the
/// read offset, when its file identity (inode) changed, or when the bytes at the start of the
/// file or just before the offset no longer match what was read: that catches a file
/// replaced in place with content at least as long as before.
nonisolated struct JSONLTailer: Sendable {
    static let defaultChunkSize = 1 << 20
    /// Bytes kept from the start of the file and from just before the offset to spot rewrites.
    static let fingerprintLength = 1024

    private struct State: Sendable {
        var offset: UInt64
        var size: UInt64
        var modified: Date
        var identity: UInt64?
        var head: Data
        var tail: Data
    }

    private let chunkSize: Int
    private var states: [URL: State] = [:]

    init(chunkSize: Int = defaultChunkSize) {
        self.chunkSize = max(1, chunkSize)
    }

    /// Regular files under `root` (recursively) whose standardized URL passes `matching`.
    static func scan(root: URL, matching: (URL) -> Bool) -> [JSONLFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return [] }
        var found: [JSONLFile] = []
        for case let raw as URL in walker {
            let url = raw.standardizedFileURL
            guard matching(url),
                  let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true,
                  let size = values.fileSize, let modified = values.contentModificationDate else { continue }
            found.append(JSONLFile(url: url, size: UInt64(size), modified: modified))
        }
        return found
    }

    func isTracked(_ url: URL) -> Bool { states[url] != nil }

    /// Stops tracking files not in `urls`; returns the forgotten ones (deleted or moved files).
    mutating func retain(_ urls: Set<URL>) -> [URL] {
        let gone = states.keys.filter { !urls.contains($0) }
        for url in gone { states[url] = nil }
        return gone
    }

    /// Delivers every complete, non-empty line appended to `file` since the last read.
    /// When the file was rewritten, `rewritten` runs first and the whole file is delivered again.
    mutating func read(_ file: JSONLFile, rewritten: () -> Void, line: (Data) -> Void) {
        let known = states[file.url]
        if let known, known.size == file.size, known.modified == file.modified { return }
        guard let handle = try? FileHandle(forReadingFrom: file.url) else { return }
        defer { try? handle.close() }

        let identity = Self.identity(of: file.url)
        var offset: UInt64 = 0
        if let known {
            if isRewrite(known, identity: identity, size: file.size, handle: handle) {
                rewritten()
            } else {
                offset = known.offset
            }
        }

        guard let consumed = readLines(handle, from: offset, line: line) else { return }
        states[file.url] = State(
            offset: consumed,
            size: file.size,
            modified: file.modified,
            identity: identity,
            head: Self.bytes(handle, at: 0, count: Int(min(consumed, UInt64(Self.fingerprintLength)))),
            tail: Self.tailBytes(handle, before: consumed)
        )
    }

    private func isRewrite(_ known: State, identity: UInt64?, size: UInt64, handle: FileHandle) -> Bool {
        if size < known.offset { return true }
        if let identity, let old = known.identity, identity != old { return true }
        return Self.bytes(handle, at: 0, count: known.head.count) != known.head
            || Self.tailBytes(handle, before: known.offset) != known.tail
    }

    /// Reads from `offset` to the end in chunks; returns the offset just past the last newline.
    private func readLines(_ handle: FileHandle, from offset: UInt64, line: (Data) -> Void) -> UInt64? {
        guard (try? handle.seek(toOffset: offset)) != nil else { return nil }
        var consumed = offset
        var pending = Data()
        while let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty {
            pending.append(chunk)
            guard let lastNewline = pending.lastIndex(of: 0x0A) else { continue }
            var start = pending.startIndex
            while start <= lastNewline, let end = pending[start...lastNewline].firstIndex(of: 0x0A) {
                if end > start { line(pending[start..<end]) }
                start = end + 1
            }
            consumed += UInt64(start - pending.startIndex)
            pending = Data(pending[start...])
        }
        return consumed
    }

    private static func tailBytes(_ handle: FileHandle, before offset: UInt64) -> Data {
        let count = min(offset, UInt64(fingerprintLength))
        return bytes(handle, at: offset - count, count: Int(count))
    }

    private static func bytes(_ handle: FileHandle, at offset: UInt64, count: Int) -> Data {
        guard count > 0, (try? handle.seek(toOffset: offset)) != nil else { return Data() }
        return (try? handle.read(upToCount: count)) ?? Data()
    }

    private static func identity(of url: URL) -> UInt64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.systemFileNumber] as? NSNumber)?.uint64Value
    }
}
