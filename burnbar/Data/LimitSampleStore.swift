//
//  LimitSampleStore.swift
//  burnbar
//

import Foundation

/// Persists each limit row's used share over time, so pace can fit a burn rate across launches.
///
/// Samples are kept per provider + row label and appended to a JSONL file
/// (`~/Library/Application Support/burnbar/limit-samples.jsonl` by default), one
/// `{"provider", "label", "t" (unix seconds), "percent"}` object per line. A sample is stored
/// only when it is newer than the row's last one and either its value changed or at least
/// `minInterval` passed. Samples older than `maxAge` are dropped: on load (malformed lines too,
/// rewriting the file when anything was dropped) and while running, rewriting the file once
/// `compactionThreshold` samples have expired.
actor LimitSampleStore {
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
    }

    private let directory: URL
    private let maxAge: TimeInterval
    private let minInterval: TimeInterval
    private let compactionThreshold: Int
    private let now: @Sendable () -> Date
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
        now: @escaping @Sendable () -> Date = Date.init
    ) {
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

    /// Records every row of `snapshot` at its `measuredAt`; a repeated snapshot adds nothing.
    func record(_ snapshot: LimitSnapshot) {
        for row in snapshot.rows {
            record(LimitSample(t: snapshot.measuredAt, percent: row.percent), provider: snapshot.provider, label: row.label)
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
            let changed = abs(sample.percent - last.percent) > 1e-9
            guard changed || sample.t.timeIntervalSince(last.t) >= minInterval else { return false }
        }
        guard sample.t >= cutoff else { return false }
        samples.append(sample)
        samplesByKey?[key] = samples

        if expiredSinceCompaction >= compactionThreshold {
            rewrite()
        } else {
            append(Record(provider: provider, label: label, t: sample.t, percent: sample.percent))
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
                    .append(LimitSample(t: record.t, percent: record.percent))
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
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: fileURL, options: .atomic)
            }
        } catch {
            // Samples stay in memory; the next compaction rewrites the file.
        }
    }

    /// Replaces the file with the samples currently in memory.
    private func rewrite() {
        expiredSinceCompaction = 0
        let encoder = Self.encoder
        var data = Data()
        let records = (samplesByKey ?? [:])
            .flatMap { key, samples in samples.map { Record(provider: key.provider, label: key.label, t: $0.t, percent: $0.percent) } }
            .sorted { $0.t < $1.t }
        for record in records {
            guard let line = try? encoder.encode(record) else { continue }
            data.append(line)
            data.append(UInt8(ascii: "\n"))
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
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
