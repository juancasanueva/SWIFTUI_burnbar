//
//  LimitSampleStore.swift
//  burnbar
//

import Foundation

/// Persists each limit row's used share over time, so pace can fit a burn rate across launches.
///
/// Samples are kept per provider + row label and appended to a JSONL file
/// (`~/Library/Application Support/burnbar/limit-samples.jsonl` by default), one
/// `{"provider", "label", "t" (unix seconds), "percent", "resetsAt"?}` object per line (lines
/// without `resetsAt` still load). A snapshot row whose reported reset has passed is not stored:
/// its reading belongs to a finished window. A sample is stored only when it is newer than the
/// row's last one and either its value or reset changed or at least `minInterval` passed. Samples older than `maxAge` are dropped: on load (malformed lines too,
/// rewriting the file when anything was dropped) and while running, rewriting the file once
/// `compactionThreshold` samples have expired.
///
/// A failed write leaves the samples in memory and marks the file dirty: the next sample
/// rewrites the whole file instead of appending, until a write succeeds.
actor LimitSampleStore: LimitSampleRecording {
    static let defaultDirectory = URL.applicationSupportDirectory.appending(path: "burnbar", directoryHint: .isDirectory)
    static let fileName = "limit-samples.jsonl"

    private nonisolated struct Key: Hashable {
        let provider: Provider
        let label: String
    }

    private nonisolated struct Record: Codable {
        let provider: Provider
        let label: String
        let t: Date
        let percent: Double
        let resetsAt: Date?
    }

    private let directory: URL
    private let maxAge: TimeInterval
    private let minInterval: TimeInterval
    private let compactionThreshold: Int
    private let now: @Sendable () -> Date
    private let writer: any LimitSampleWriting
    /// Set when a write failed, so the file misses samples that are in memory.
    private var fileIsDirty = false
    /// Nil until the file is first read.
    private var samplesByKey: [Key: [LimitSample]]?
    /// Samples expired in memory since the file was last rewritten.
    private var expiredSinceCompaction = 0

    private var fileURL: URL { directory.appending(path: Self.fileName) }

    init(
        directory: URL = defaultDirectory,
        maxAge: TimeInterval = 7 * 24 * 3600,
        minInterval: TimeInterval = 300,
        compactionThreshold: Int = 1000,
        writer: any LimitSampleWriting = FileLimitSampleWriter(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.writer = writer
        self.directory = directory
        self.maxAge = maxAge
        self.minInterval = minInterval
        self.compactionThreshold = compactionThreshold
        self.now = now
    }

    /// Samples of one row, oldest first, within `maxAge`.
    func samples(provider: Provider, label: String) -> [LimitSample] {
        prune()
        return samplesByKey?[Key(provider: provider, label: label)] ?? []
    }

    /// Records every row of `snapshot` at its `measuredAt`, with the row's reported reset; a
    /// repeated snapshot adds nothing, nor does a row whose reset has passed.
    func record(_ snapshot: LimitSnapshot) {
        let now = now()
        for row in snapshot.rows where row.resetsAt > now {
            record(LimitSample(t: snapshot.measuredAt, percent: row.percent, resetsAt: row.resetsAt),
                   provider: snapshot.provider, label: row.label)
        }
    }

    /// - Returns: Whether the sample was stored.
    @discardableResult
    func record(_ sample: LimitSample, provider: Provider, label: String) -> Bool {
        prune()
        let key = Key(provider: provider, label: label)
        var samples = samplesByKey?[key] ?? []
        if let last = samples.last {
            guard sample.t > last.t else { return false }
            let changed = abs(sample.percent - last.percent) > 1e-9 || sample.resetsAt != last.resetsAt
            guard changed || sample.t.timeIntervalSince(last.t) >= minInterval else { return false }
        }
        guard sample.t >= cutoff else { return false }
        samples.append(sample)
        samplesByKey?[key] = samples

        if fileIsDirty || expiredSinceCompaction >= compactionThreshold {
            rewrite()
        } else {
            append(Record(provider: provider, label: label, t: sample.t, percent: sample.percent, resetsAt: sample.resetsAt))
        }
        return true
    }

    private var cutoff: Date { now().addingTimeInterval(-maxAge) }

    /// Loads the file on first use, then drops expired samples from memory.
    private func prune() {
        guard let current = samplesByKey else {
            load()
            return
        }
        let cutoff = cutoff
        var pruned: [Key: [LimitSample]] = [:]
        for (key, samples) in current {
            let kept = samples.filter { $0.t >= cutoff }
            expiredSinceCompaction += samples.count - kept.count
            if !kept.isEmpty { pruned[key] = kept }
        }
        samplesByKey = pruned
    }

    private func load() {
        let cutoff = cutoff
        var loaded: [Key: [LimitSample]] = [:]
        var dropped = 0
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            let decoder = Self.decoder
            for line in text.split(separator: "\n") {
                guard let record = try? decoder.decode(Record.self, from: Data(line.utf8)), record.t >= cutoff else {
                    dropped += 1
                    continue
                }
                loaded[Key(provider: record.provider, label: record.label), default: []]
                    .append(LimitSample(t: record.t, percent: record.percent, resetsAt: record.resetsAt))
            }
        }
        samplesByKey = loaded.mapValues { $0.sorted { $0.t < $1.t } }
        if dropped > 0 { rewrite() }
    }

    private func append(_ record: Record) {
        guard var line = try? Self.encoder.encode(record) else { return }
        line.append(UInt8(ascii: "\n"))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writer.append(line, to: fileURL)
        } catch {
            // The sample stays in memory; the next one rewrites the whole file.
            fileIsDirty = true
        }
    }

    /// Replaces the file with the samples currently in memory.
    private func rewrite() {
        expiredSinceCompaction = 0
        let encoder = Self.encoder
        var data = Data()
        let records = (samplesByKey ?? [:])
            .flatMap { key, samples in samples.map {
                Record(provider: key.provider, label: key.label, t: $0.t, percent: $0.percent, resetsAt: $0.resetsAt)
            } }
            .sorted { $0.t < $1.t }
        for record in records {
            guard let line = try? encoder.encode(record) else { continue }
            data.append(line)
            data.append(UInt8(ascii: "\n"))
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writer.replace(data, at: fileURL)
            fileIsDirty = false
        } catch {
            fileIsDirty = true
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = .sortedKeys
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}

/// Records limit snapshots and returns each row's samples, for pace rate fitting.
nonisolated protocol LimitSampleRecording: Sendable {
    func record(_ snapshot: LimitSnapshot) async
    /// Samples of one row, oldest first.
    func samples(provider: Provider, label: String) async -> [LimitSample]
}

/// Writes the sample file; injectable so write failures can be tested.
nonisolated protocol LimitSampleWriting: Sendable {
    /// Appends one newline-terminated line, creating the file when missing.
    func append(_ line: Data, to url: URL) throws
    /// Atomically replaces the file with `contents`.
    func replace(_ contents: Data, at url: URL) throws
}

/// File-system writer. Appending first terminates a torn last line (e.g. from a crash mid-write),
/// so it cannot swallow the new record.
nonisolated struct FileLimitSampleWriter: LimitSampleWriting {
    func append(_ line: Data, to url: URL) throws {
        guard let handle = try? FileHandle(forUpdating: url) else {
            try line.write(to: url, options: .atomic)
            return
        }
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        var data = line
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != Data([UInt8(ascii: "\n")]) {
                data.insert(UInt8(ascii: "\n"), at: 0)
            }
            try handle.seekToEnd()
        }
        try handle.write(contentsOf: data)
    }

    func replace(_ contents: Data, at url: URL) throws {
        try contents.write(to: url, options: .atomic)
    }
}
