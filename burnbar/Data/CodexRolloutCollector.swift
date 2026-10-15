//
//  CodexRolloutCollector.swift
//  burnbar
//

import Foundation

/// Incrementally collects Codex burn and rate limits from `~/.codex/sessions/**/rollout-*.jsonl`.
///
/// Burn: each rollout file is tailed with a `JSONLTailer` and its cumulative `token_count`
/// totals become per-turn deltas (`CodexBurnTracker`). A rewritten file's events are dropped
/// and derived again from its new content; a deleted file's events are dropped. Events are
/// pruned past the window plus a margin, and untracked files last modified before that cutoff
/// are not tailed.
///
/// Limits: the newest `rate_limits` record (by timestamp) seen in any tailed file. When none is
/// known, the newest untracked rollout files are probed by reading only their last chunk, so
/// limits show up even when Codex was not used within the window.
actor CodexRolloutCollector: UsageCollector, LimitsSource {
    static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".codex/sessions", directoryHint: .isDirectory)
    /// Bytes read from the end of an untracked file when probing it for limits.
    static let probeLength = 256 * 1024
    /// Untracked files probed per refresh, newest first.
    static let probeCount = 3

    private struct FileBurn {
        var tracker = CodexBurnTracker()
        var events: [UsageEvent] = []
    }

    private let root: URL
    private let retention: TimeInterval
    private var tailer: JSONLTailer
    private var burns: [URL: FileBurn] = [:]
    private var newestLimits: CodexTokenCount?
    private var probed: Set<JSONLFile> = []

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
        refresh(now: now)
        return burns.values.flatMap(\.events).sorted { $0.timestamp < $1.timestamp }
    }

    func limits(now: Date) -> LimitSnapshot? {
        refresh(now: now)
        return newestLimits.flatMap(CodexRolloutParser.snapshot(from:))
    }

    private func refresh(now: Date) {
        let cutoff = now.addingTimeInterval(-retention)
        let found = JSONLTailer.scan(root: root) {
            $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("rollout-")
        }
        var untracked: [JSONLFile] = []
        for file in found {
            if tailer.isTracked(file.url) || file.modified >= cutoff {
                read(file)
            } else {
                untracked.append(file)
            }
        }
        for url in tailer.retain(Set(found.map(\.url))) { burns[url] = nil }
        for url in burns.keys { burns[url]?.events.removeAll { $0.timestamp < cutoff } }

        if newestLimits == nil { probe(untracked) }
    }

    private func read(_ file: JSONLFile) {
        let sessionID = file.url.deletingPathExtension().lastPathComponent
        var burn = burns[file.url] ?? FileBurn()
        tailer.read(file, rewritten: { burn = FileBurn() }, line: { line in
            guard let record = CodexRolloutParser.record(from: line) else { return }
            if case .tokenCount(let count) = record { offerLimits(count) }
            if let event = burn.tracker.ingest(record, sessionID: sessionID) { burn.events.append(event) }
        })
        burns[file.url] = burn
    }

    /// Reads the tail of the newest files not tailed yet; each file version is probed once.
    private func probe(_ files: [JSONLFile]) {
        let candidates = files.filter { !probed.contains($0) }.sorted { $0.modified > $1.modified }
        for file in candidates.prefix(Self.probeCount) {
            probed.insert(file)
            JSONLTailer.lastLines(of: file.url, maxBytes: Self.probeLength) { line in
                if case .tokenCount(let count) = CodexRolloutParser.record(from: line) { offerLimits(count) }
            }
            if newestLimits != nil { return }
        }
    }

    private func offerLimits(_ count: CodexTokenCount) {
        guard count.hasRateLimits else { return }
        if let kept = newestLimits, kept.timestamp > count.timestamp { return }
        newestLimits = count
    }
}
