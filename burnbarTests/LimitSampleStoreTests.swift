//
//  LimitSampleStoreTests.swift
//  burnbarTests
//

import Foundation
import Synchronization
import Testing
@testable import burnbar

/// A settable clock for stores that prune by age.
final class TestClock: Sendable {
    private let instant: Mutex<Date>
    init(_ date: Date) { instant = Mutex(date) }
    var now: Date { instant.withLock { $0 } }
    func advance(_ interval: TimeInterval) { instant.withLock { $0 = $0.addingTimeInterval(interval) } }
}

final class LimitSampleStoreTests {
    private let directory: URL
    private let clock = TestClock(now)
    private let weekly = "Weekly (7-day)"

    init() throws {
        directory = try makeTemporaryDirectory().appending(path: "burnbar", directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    private var file: URL { directory.appending(path: "limit-samples.jsonl") }

    private func store(maxAge: TimeInterval = 7 * 24 * hour, compactionThreshold: Int = 1000) -> LimitSampleStore {
        let clock = clock
        return LimitSampleStore(directory: directory, maxAge: maxAge, compactionThreshold: compactionThreshold, now: { clock.now })
    }

    private func lines() throws -> [String] {
        try String(contentsOf: file, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    private func record(_ store: LimitSampleStore, _ provider: Provider = .claude, label: String? = nil, at offset: TimeInterval, _ percent: Double) async -> Bool {
        await store.record(sample(at: offset, percent), provider: provider, label: label ?? weekly)
    }

    @Test func appendsOnChangeOrAfterFiveMinutes() async throws {
        let sut = store()
        #expect(await record(sut, at: -900, 0.10))
        #expect(await record(sut, at: -840, 0.10) == false)
        #expect(await record(sut, at: -780, 0.12))
        #expect(await record(sut, at: -780 + 299, 0.12) == false)
        #expect(await record(sut, at: -780 + 300, 0.12))
        #expect(await sut.samples(provider: .claude, label: weekly) == [sample(at: -900, 0.10), sample(at: -780, 0.12), sample(at: -480, 0.12)])
        #expect(try lines().count == 3)
    }

    @Test func ignoresSamplesNotNewerThanTheLast() async throws {
        let sut = store()
        #expect(await record(sut, at: -600, 0.10))
        #expect(await record(sut, at: -600, 0.20) == false)
        #expect(await record(sut, at: -1200, 0.30) == false)
        #expect(await sut.samples(provider: .claude, label: weekly) == [sample(at: -600, 0.10)])
    }

    @Test func keepsProvidersAndLabelsApart() async throws {
        let sut = store()
        #expect(await record(sut, .claude, at: -60, 0.1))
        #expect(await record(sut, .codex, at: -60, 0.1))
        #expect(await record(sut, .claude, label: "Session (5-hour)", at: -60, 0.1))
        #expect(await sut.samples(provider: .codex, label: weekly) == [sample(at: -60, 0.1)])
        #expect(await sut.samples(provider: .codex, label: "Session (5-hour)").isEmpty)
        #expect(await sut.samples(provider: .claude, label: "Session (5-hour)").count == 1)
    }

    @Test func recordsEverySnapshotRowAtItsMeasuredTime() async throws {
        let sut = store()
        let measured = now.addingTimeInterval(-120)
        let snapshot = LimitSnapshot(provider: .claude, rows: [
            LimitRow(label: "Session (5-hour)", percent: 0.4, resetsAt: now, windowDuration: fiveHours),
            LimitRow(label: weekly, percent: 0.2, resetsAt: now, windowDuration: week),
        ], measuredAt: measured)
        await sut.record(snapshot)
        // The same (stale) snapshot again adds nothing.
        await sut.record(snapshot)
        #expect(await sut.samples(provider: .claude, label: "Session (5-hour)") == [LimitSample(t: measured, percent: 0.4)])
        #expect(await sut.samples(provider: .claude, label: weekly) == [LimitSample(t: measured, percent: 0.2)])
        #expect(try lines().count == 2)
    }

    @Test func persistsAcrossInstances() async throws {
        let first = store()
        #expect(await record(first, at: -600, 0.25))
        #expect(await record(first, .codex, at: -300, 0.5))

        let second = store()
        #expect(await second.samples(provider: .claude, label: weekly) == [sample(at: -600, 0.25)])
        #expect(await second.samples(provider: .codex, label: weekly) == [sample(at: -300, 0.5)])
        // The reloaded last sample still gates appends.
        #expect(await record(second, at: -540, 0.25) == false)
    }

    @Test func dropsOldAndMalformedLinesOnLoadAndCompacts() async throws {
        let old = #"{"provider":"claude","label":"Weekly (7-day)","t":\#(now.timeIntervalSince1970 - 8 * 24 * hour),"percent":0.1}"#
        let recent = #"{"provider":"claude","label":"Weekly (7-day)","t":\#(now.timeIntervalSince1970 - 3600),"percent":0.2}"#
        let unknownProvider = #"{"provider":"grok","label":"Weekly (7-day)","t":\#(now.timeIntervalSince1970),"percent":0.3}"#
        try writeLines([old, "garbage", recent, unknownProvider], to: file)

        let sut = store()
        #expect(await sut.samples(provider: .claude, label: weekly) == [sample(at: -3600, 0.2)])
        #expect(try lines().count == 1)
    }

    @Test func compactsWhileRunningOnceEnoughSamplesExpire() async throws {
        let sut = store(maxAge: 1000, compactionThreshold: 2)
        #expect(await record(sut, at: -500, 0.1))
        #expect(await record(sut, at: -400, 0.2))
        clock.advance(600)
        // Only the -500 sample has expired: below the threshold, the file keeps it.
        #expect(await record(sut, at: 400, 0.3))
        #expect(await sut.samples(provider: .claude, label: weekly).map(\.percent) == [0.2, 0.3])
        #expect(try lines().count == 3)

        clock.advance(200)
        #expect(await record(sut, at: 600, 0.4))
        #expect(await sut.samples(provider: .claude, label: weekly).map(\.percent) == [0.3, 0.4])
        #expect(try lines().count == 2)
    }

    // MARK: Write failures and torn lines

    @Test func aFailedAppendIsWrittenWithTheNextSample() async throws {
        let writer = FlakyWriter(failures: 1)
        let clock = clock
        let sut = LimitSampleStore(directory: directory, writer: writer, now: { clock.now })
        #expect(await record(sut, at: -600, 0.1))
        #expect(FileManager.default.fileExists(atPath: file.path) == false)

        #expect(await record(sut, at: -300, 0.2))
        #expect(writer.replacements == 1)
        #expect(await store().samples(provider: .claude, label: weekly).map(\.percent) == [0.1, 0.2])
    }

    @Test func aFailedRewriteStaysPendingUntilAWriteSucceeds() async throws {
        let writer = FlakyWriter(failures: 2)
        let clock = clock
        let sut = LimitSampleStore(directory: directory, writer: writer, now: { clock.now })
        #expect(await record(sut, at: -900, 0.1))
        #expect(await record(sut, at: -600, 0.2))
        #expect(await record(sut, at: -300, 0.3))
        #expect(await store().samples(provider: .claude, label: weekly).map(\.percent) == [0.1, 0.2, 0.3])
        // Back to appending once the file is whole again.
        #expect(await record(sut, at: -60, 0.4))
        #expect(writer.appends == 1)
    }

    @Test func appendingAfterATornLineStartsANewLine() async throws {
        let sut = store()
        #expect(await record(sut, at: -600, 0.1))
        try appendText(#"{"provider":"claude","label":"Weekly"#, to: file)

        #expect(await record(sut, at: -300, 0.2))
        #expect(try lines().count == 3)
        #expect(await store().samples(provider: .claude, label: weekly).map(\.percent) == [0.1, 0.2])
    }
}

/// The real file writer, failing its first `failures` calls.
final class FlakyWriter: LimitSampleWriting {
    private struct State {
        var failures: Int
        var appends = 0
        var replacements = 0
    }

    private let state: Mutex<State>
    private let real = FileLimitSampleWriter()

    init(failures: Int) { state = Mutex(State(failures: failures)) }

    var appends: Int { state.withLock { $0.appends } }
    var replacements: Int { state.withLock { $0.replacements } }

    private func failIfDue() throws {
        let fail = state.withLock { state in
            guard state.failures > 0 else { return false }
            state.failures -= 1
            return true
        }
        if fail { throw CocoaError(.fileWriteUnknown) }
    }

    func append(_ line: Data, to url: URL) throws {
        try failIfDue()
        try real.append(line, to: url)
        state.withLock { $0.appends += 1 }
    }

    func replace(_ contents: Data, at url: URL) throws {
        try failIfDue()
        try real.replace(contents, at: url)
        state.withLock { $0.replacements += 1 }
    }
}
