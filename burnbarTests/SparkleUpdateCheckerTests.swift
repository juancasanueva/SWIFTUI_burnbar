//
//  SparkleUpdateCheckerTests.swift
//  burnbarTests
//
//  The production Sparkle adapter, driven through its `SparkleUpdaterDriving` seam: launch
//  order, which side owns the automatic-check answer, the setter's write order, and change
//  notifications that arrive off the main thread.
//

import Foundation
import Testing
@testable import burnbar

/// Records every call the adapter makes, in order, so ordering claims are checkable.
@MainActor
final class FakeSparkleUpdater: SparkleUpdaterDriving {
    enum Call: Equatable {
        case setAutomatic(Bool)
        case start
        case check
    }

    private(set) var calls: [Call] = []
    var canCheckForUpdates = true
    var lastUpdateCheckDate: Date?
    /// Sparkle's own copy of the flag, which the adapter must never treat as the authority.
    var storedAutomatic: Bool
    /// Runs inside the automatic-check write, before it returns.
    var onAutomaticWrite: (() -> Void)?
    private(set) var onChange: (@Sendable () -> Void)?

    init(storedAutomatic: Bool = false) {
        self.storedAutomatic = storedAutomatic
    }

    var automaticallyChecksForUpdates: Bool {
        get { storedAutomatic }
        set {
            storedAutomatic = newValue
            calls.append(.setAutomatic(newValue))
            onAutomaticWrite?()
        }
    }

    func startUpdater() { calls.append(.start) }
    func checkForUpdates() { calls.append(.check) }

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyObject {
        self.onChange = onChange
        return NSObject()
    }
}

@MainActor
@Suite("Sparkle update checker")
struct SparkleUpdateCheckerTests {
    /// A defaults domain that exists only for this test, and is removed after it.
    private func withScratchSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "burnbar-tests-sparkle-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: name) else {
            Issue.record("could not create the scratch defaults suite")
            return
        }
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    /// Sparkle starts out disagreeing with the app, so a launch that skipped the write, or wrote
    /// after starting, fails in both directions.
    @Test(arguments: [true, false])
    func thePersistedPreferenceIsAppliedBeforeTheUpdaterStarts(preference: Bool) {
        withScratchSuite { defaults in
            let automaticChecks = AutomaticUpdateChecks(defaults: defaults)
            automaticChecks.isEnabled = preference
            let sparkle = FakeSparkleUpdater(storedAutomatic: !preference)

            _ = SparkleUpdateChecker(automaticChecks: automaticChecks, updater: sparkle)

            #expect(sparkle.calls == [.setAutomatic(preference), .start])
        }
    }

    /// Sparkle persisting its own answer behind the app's back changes nothing the surfaces read.
    @Test func theGetterReadsTheAppKeyNotSparkle() {
        withScratchSuite { defaults in
            let sparkle = FakeSparkleUpdater()
            let checker = SparkleUpdateChecker(automaticChecks: AutomaticUpdateChecks(defaults: defaults),
                                               updater: sparkle)

            sparkle.storedAutomatic = true

            #expect(checker.automaticallyChecksForUpdates == false)
        }
    }

    /// While Sparkle is being written the app key still holds the old answer; afterwards both agree.
    @Test(arguments: [true, false])
    func theSetterWritesSparkleFirstThenTheAppKey(newValue: Bool) {
        withScratchSuite { defaults in
            let automaticChecks = AutomaticUpdateChecks(defaults: defaults)
            automaticChecks.isEnabled = !newValue
            let sparkle = FakeSparkleUpdater()
            let checker = SparkleUpdateChecker(automaticChecks: automaticChecks, updater: sparkle)
            var appKeyDuringSparkleWrite: Bool?
            sparkle.onAutomaticWrite = { appKeyDuringSparkleWrite = automaticChecks.isEnabled }

            checker.automaticallyChecksForUpdates = newValue

            #expect(appKeyDuringSparkleWrite == !newValue)
            #expect(sparkle.storedAutomatic == newValue)
            #expect(automaticChecks.isEnabled == newValue)
        }
    }

    @Test func eachInvocationStartsExactlyOneCheck() {
        withScratchSuite { defaults in
            let sparkle = FakeSparkleUpdater()
            let checker = SparkleUpdateChecker(automaticChecks: AutomaticUpdateChecks(defaults: defaults),
                                               updater: sparkle)

            checker.checkForUpdates()
            checker.checkForUpdates()

            #expect(sparkle.calls.filter { $0 == .check }.count == 2)
        }
    }

    /// On the main thread the mirror updates before the callback returns: no window in which the
    /// command looks enabled while a check is already running.
    @Test func aMainThreadChangeIsMirroredImmediately() throws {
        try withScratchSuite { defaults in
            let sparkle = FakeSparkleUpdater()
            let checker = SparkleUpdateChecker(automaticChecks: AutomaticUpdateChecks(defaults: defaults),
                                               updater: sparkle)
            let onChange = try #require(sparkle.onChange)
            let checked = Date(timeIntervalSince1970: 1_787_000_000)

            sparkle.canCheckForUpdates = false
            sparkle.lastUpdateCheckDate = checked
            onChange()

            #expect(checker.canCheckForUpdates == false)
            #expect(checker.lastUpdateCheckDate == checked)
        }
    }

    /// A change posted from a background thread must not trap; it reaches the mirror on the main
    /// actor shortly after.
    @Test func anOffMainChangeHopsToTheMainActor() async throws {
        let name = "burnbar-tests-sparkle-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let sparkle = FakeSparkleUpdater()
        let checker = SparkleUpdateChecker(automaticChecks: AutomaticUpdateChecks(defaults: defaults),
                                           updater: sparkle)
        let onChange = try #require(sparkle.onChange)

        sparkle.canCheckForUpdates = false
        await Task.detached {
            #expect(Thread.isMainThread == false)
            onChange()
        }.value
        for _ in 0..<100 where checker.canCheckForUpdates {
            await Task.yield()
        }

        #expect(checker.canCheckForUpdates == false)
    }
}
