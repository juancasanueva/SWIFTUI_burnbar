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

    /// The release ships arm64 only, so the cask can depend on it: both configurations pin it
    /// rather than leaving it to the command line in `scripts/release.sh`.
    @Test func bothAppConfigurationsBuildArm64Only() throws {
        #expect(try ProjectSources.appTargetBlocksDeclaring("ARCHS = arm64;") == 2)
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
            if text.components(separatedBy: "\n").contains(where: Self.importsSparkle) {
                importers.append(url.lastPathComponent)
            }
        }
        #expect(importers == ["SparkleUpdateChecker.swift"])
    }

    /// The guard's matcher sees through indentation and import attributes, and only matches the
    /// Sparkle module itself.
    @Test(arguments: [
        "import Sparkle",
        "    import Sparkle",
        "\timport Sparkle",
        "@preconcurrency import Sparkle",
        "@_implementationOnly import Sparkle",
        "public import Sparkle",
        "@preconcurrency public import Sparkle",
        "import class Sparkle.SPUUpdater",
        "import Sparkle.SPUUpdater",
        "import Sparkle // the adapter",
    ])
    func theGuardCatchesEveryImportSpelling(line: String) {
        #expect(Self.importsSparkle(line))
    }

    @Test(arguments: ["import SparkleKit", "// import Sparkle", "let text = \"import Sparkle\"", "import Foundation"])
    func theGuardIgnoresLinesThatDoNotImportSparkle(line: String) {
        #expect(Self.importsSparkle(line) == false)
    }

    /// Whether one source line imports the Sparkle module (or a declaration from it).
    /// Leading attributes (`@preconcurrency`, `@_implementationOnly`, `@_spi(…)`) and access
    /// modifiers are skipped, then `import`, an optional declaration kind, and the module path.
    static func importsSparkle(_ line: String) -> Bool {
        let modifiers: Set<String> = ["public", "package", "internal", "fileprivate", "private"]
        let kinds: Set<String> = ["class", "struct", "enum", "protocol", "typealias", "func", "var", "let"]
        var tokens = line.split(whereSeparator: \.isWhitespace).map(String.init)[...]
        while let first = tokens.first, first.hasPrefix("@") || modifiers.contains(first) {
            tokens = tokens.dropFirst()
        }
        guard tokens.first == "import" else { return false }
        tokens = tokens.dropFirst()
        if let kind = tokens.first, kinds.contains(kind) { tokens = tokens.dropFirst() }
        guard let path = tokens.first else { return false }
        return path.split(separator: ".").first == "Sparkle"
    }
}
