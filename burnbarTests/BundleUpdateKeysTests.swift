//
//  BundleUpdateKeysTests.swift
//  burnbarTests
//
//  The update feed and verification key, read from `Bundle.main` (the delivered values) and
//  from the partial property list on disk (what the repository declares).
//

import Foundation
import Testing

@Suite("Bundle update keys")
struct BundleUpdateKeysTests {
    private static let partialInfoPlist = "burnbar/Resources/Burnbar-Info.plist"
    private static let feedURL = "https://juancasanueva.github.io/SWIFTUI_burnbar/appcast.xml"
    private static let publicKey = "jqReS/cOvK94pbRz/4DwMBTRMwh/0Nf5OJZ5SAfZDVs="

    /// Keys Sparkle reads to decide on its own whether to check. None may be bundled: the app's
    /// persisted preference is the authority, written to the updater at launch.
    private static let frameworkAutomaticCheckKeys = [
        "SUEnableAutomaticChecks",
        "SUAutomaticallyUpdate",
        "SUScheduledCheckInterval",
    ]

    /// Parsed the way the build system parses it: a file that looks right and does not parse is
    /// a build failure nobody sees until an archive.
    private static func partialInfoPlistContents() throws -> [String: Any] {
        let url = ProjectSources.repositoryRoot.appendingPathComponent(partialInfoPlist)
        let parsed = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(parsed as? [String: Any])
    }

    /// The exact feed over https, and a key that decodes to 32 bytes: a 44-character string only
    /// looks like an Ed25519 public key, and `Data(base64Encoded:)` returns nil for noise.
    @Test func theBundleCarriesTheFeedAndA32ByteVerificationKey() throws {
        let info = try #require(Bundle.main.infoDictionary)

        let feed = try #require(info["SUFeedURL"] as? String)
        #expect(feed == Self.feedURL)
        #expect(URL(string: feed)?.scheme == "https")

        let key = try #require(info["SUPublicEDKey"] as? String)
        #expect(key == Self.publicKey)
        #expect(try #require(Data(base64Encoded: key)).count == 32)
    }

    /// The merge keeps the generated keys: the app stays out of the Dock.
    @Test func theMergeKeepsTheGeneratedKeys() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(info["LSUIElement"] as? Bool == true)
        #expect(info["CFBundleIdentifier"] as? String == "com.juancasanueva.burnbar")
    }

    /// An exact key set rather than an absence list, in the file and in the merged bundle.
    @Test func thePartialPropertyListCarriesOnlyTheFeedAndTheKey() throws {
        let contents = try Self.partialInfoPlistContents()

        #expect(contents.keys.sorted() == ["SUFeedURL", "SUPublicEDKey"])
        #expect(contents["SUFeedURL"] as? String == Self.feedURL)

        let info = try #require(Bundle.main.infoDictionary)
        for key in Self.frameworkAutomaticCheckKeys {
            #expect(info[key] == nil, "\(key) reached the merged bundle")
        }
    }

    /// The partial property list is merged into the generated one, not copied as a resource.
    @Test func thePartialPropertyListIsNotABundleResource() {
        #expect(Bundle.main.url(forResource: "Burnbar-Info", withExtension: "plist") == nil)
    }
}
