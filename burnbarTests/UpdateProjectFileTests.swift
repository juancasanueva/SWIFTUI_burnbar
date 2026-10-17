//
//  UpdateProjectFileTests.swift
//  burnbarTests
//
//  The updater dependency and the property-list merge, as the project file declares them.
//

import Foundation
import Testing

@Suite("Update project file")
struct UpdateProjectFileTests {
    private static let partialInfoPlist = "INFOPLIST_FILE = \"burnbar/Resources/Burnbar-Info.plist\";"

    /// A merge, not a replacement: every generated key (LSUIElement included) only survives while
    /// the generator stays on, in both configurations.
    @Test func bothAppConfigurationsMergeThePartialPropertyList() throws {
        #expect(try ProjectSources.appTargetBlocksDeclaring(Self.partialInfoPlist) == 2)
        #expect(try ProjectSources.appTargetBlocksDeclaring("GENERATE_INFOPLIST_FILE = YES;") == 2)
        #expect(try ProjectSources.appTargetBlocksDeclaring("INFOPLIST_KEY_LSUIElement = YES;") == 2)
    }

    /// Sparkle replaces the bundle in place, so the app is unsandboxed; the hardened runtime stays.
    @Test func bothAppConfigurationsShipUnsandboxedWithTheHardenedRuntime() throws {
        #expect(try ProjectSources.appTargetBlocksDeclaring("ENABLE_APP_SANDBOX = NO;") == 2)
        #expect(try ProjectSources.appTargetBlocksDeclaring("ENABLE_HARDENED_RUNTIME = YES;") == 2)
    }

    /// Exactly one Sparkle package, pinned to exactVersion 2.9.6, linked once by the app, and no
    /// embed phase: Sparkle auto-embeds, so an Embed Frameworks phase would double-sign it.
    @Test func theProjectLinksExactlyOnePinnedSparklePackageWithNoEmbedPhase() throws {
        let project = try ProjectSources.projectText()

        let remote = ProjectSources.objectBlocks(inSection: "XCRemoteSwiftPackageReference", of: project)
        let sparkle = try #require(
            remote.first { $0.contains("repositoryURL = \"https://github.com/sparkle-project/Sparkle\";") }
        )
        #expect(remote.count == 1)
        #expect(sparkle.contains("kind = exactVersion;"))
        #expect(sparkle.contains("version = 2.9.6;"))

        let buildFiles = ProjectSources.section("PBXBuildFile", in: project)
        #expect(ProjectSources.occurrences(of: "/* Sparkle in Frameworks */ = {isa = PBXBuildFile;", in: buildFiles) == 1)

        let phases = ProjectSources.objectBlocks(inSection: "PBXFrameworksBuildPhase", of: project)
        #expect(phases.filter { $0.contains("/* Sparkle in Frameworks */,") }.count == 1)

        let products = ProjectSources.objectBlocks(inSection: "XCSwiftPackageProductDependency", of: project)
        #expect(products.filter { $0.contains("productName = Sparkle;") }.count == 1)

        #expect(ProjectSources.occurrences(of: "PBXCopyFilesBuildPhase", in: project) == 0)
    }

    /// The resolved pin agrees with the declared requirement.
    @Test func theResolvedPinIsSparkle296() throws {
        let url = ProjectSources.repositoryRoot
            .appendingPathComponent("burnbar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved")
        let resolved = try String(contentsOf: url, encoding: .utf8)
        #expect(resolved.contains("\"location\" : \"https://github.com/sparkle-project/Sparkle\""))
        #expect(resolved.contains("\"version\" : \"2.9.6\""))
    }

    /// Only the adapter names the framework; everything else speaks to `AppUpdating`.
    @Test func onlyTheAdapterImportsSparkle() throws {
        let sources = ProjectSources.repositoryRoot.appendingPathComponent("burnbar")
        let enumerator = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        var importers: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.components(separatedBy: "\n").contains(where: { $0.hasPrefix("import Sparkle") }) {
                importers.append(url.lastPathComponent)
            }
        }
        #expect(importers == ["SparkleUpdateChecker.swift"])
    }
}
