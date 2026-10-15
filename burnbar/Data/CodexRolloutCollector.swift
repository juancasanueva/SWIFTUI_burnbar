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
/// Limits: the newest `rate_limits` record (by timestamp) among the files still on disk. Each
/// file keeps its own newest record, so a rewritten file's record is derived again and a deleted
/// file's record is dropped, letting the next newest one take over. When no tailed file has one,
/// the most recently modified untracked rollout files are probed by reading only their last
/// chunk (up to `probeCount` per refresh, each file version once), so limits show up even when
/// Codex was not used within the window. A probed record lasts while its file is unchanged.
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
    /// Newest rate-limit record per tailed file.
    private var tailedLimits: [URL: CodexTokenCount] = [:]
    /// Newest rate-limit record per probed file version.
    private var probedLimits: [JSONLFile: CodexTokenCount] = [:]
    private var probed: Set<JSONLFile> = []
    private let probeCount: Int
    private let onProbe: @Sendable (URL) -> Void

    /// - Parameters:
    ///   - window: Trailing window the app displays (360 min).
    ///   - margin: Extra history kept past the window so a late refresh never loses an edge turn.
    init(
        root: URL = defaultRoot,
        window: TimeInterval = 360 * 60,
        margin: TimeInterval = 30 * 60,
        chunkSize: Int = JSONLTailer.defaultChunkSize,
        probeCount: Int = probeCount,
        onProbe: @escaping @Sendable (URL) -> Void = { _ in }
    ) {
        self.probeCount = probeCount
        self.onProbe = onProbe
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

    private var newestLimits: CodexTokenCount? {
        Self.newer(tailedLimits.values.max { $0.timestamp < $1.timestamp }, probedLimits.values.max { $0.timestamp < $1.timestamp })
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
        for url in tailer.retain(Set(found.map(\.url))) {
            burns[url] = nil
            tailedLimits[url] = nil
        }
        for url in burns.keys { burns[url]?.events.removeAll { $0.timestamp < cutoff } }

        // A probed version no longer untracked as-is (deleted, changed or now tailed) is stale.
        let stillUntracked = Set(untracked)
        probedLimits = probedLimits.filter { stillUntracked.contains($0.key) }
        probed.formIntersection(stillUntracked)
        if newestLimits == nil { probe(untracked) }
    }

    private func read(_ file: JSONLFile) {
        let sessionID = file.url.deletingPathExtension().lastPathComponent
        var burn = burns[file.url] ?? FileBurn()
        var limits = tailedLimits[file.url]
        tailer.read(file, rewritten: {
            burn = FileBurn()
            limits = nil
        }, line: { line in
            guard let record = CodexRolloutParser.record(from: line) else { return }
            if case .tokenCount(let count) = record { limits = Self.newer(limits, count) }
            if let event = burn.tracker.ingest(record, sessionID: sessionID) { burn.events.append(event) }
        })
        burns[file.url] = burn
        tailedLimits[file.url] = limits
    }

    /// Reads the tail of the most recently modified files not probed yet, stopping at the first
    /// one with a rate-limit record.
    private func probe(_ files: [JSONLFile]) {
        let candidates = files.filter { !probed.contains($0) }.sorted { $0.modified > $1.modified }
        for file in candidates.prefix(probeCount) {
            probed.insert(file)
            onProbe(file.url)
            var limits: CodexTokenCount?
            JSONLTailer.lastLines(of: file.url, maxBytes: Self.probeLength) { line in
                if case .tokenCount(let count) = CodexRolloutParser.record(from: line) { limits = Self.newer(limits, count) }
            }
            if let limits {
                probedLimits[file] = limits
                return
            }
        }
    }

    /// The record with rate limits and the later timestamp; `kept` wins ties.
    private static func newer(_ kept: CodexTokenCount?, _ candidate: CodexTokenCount?) -> CodexTokenCount? {
        guard let candidate, candidate.hasRateLimits else { return kept }
        guard let kept else { return candidate }
        return kept.timestamp > candidate.timestamp ? kept : candidate
    }
}
