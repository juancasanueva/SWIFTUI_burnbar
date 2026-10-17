//
//  ProjectFileTests.swift
//  burnbarTests
//
//  Structural checks over `burnbar.xcodeproj/project.pbxproj`, read off disk as text: these
//  are claims about what the repository declares, not about what the test host contains.
//

import Foundation
import Testing

/// Reads the project file and cuts it into the blocks the assertions need.
nonisolated enum ProjectSources {
    static let projectFile = "burnbar.xcodeproj/project.pbxproj"

    /// Anchored to this file because the test runner promises nothing about the working directory.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // burnbarTests
            .deletingLastPathComponent()   // repository root
    }

    static func projectText() throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(projectFile), encoding: .utf8)
    }

    /// Every `XCBuildConfiguration` body, from its `isa` line to the two-tab `};` that closes it
    /// (the three-tab `};` closing `buildSettings` cannot be mistaken for it). A setting is
    /// asserted per block, so a value present in Debug only does not pass for both.
    static func buildConfigurationBlocks() throws -> [String] {
        let marker = "isa = XCBuildConfiguration;"
        let terminator = "\n\t\t};"
        return try projectText()
            .components(separatedBy: marker)
            .dropFirst()
            .map { chunk in
                guard let end = chunk.range(of: terminator) else { return chunk }
                return String(chunk[chunk.startIndex..<end.lowerBound])
            }
    }

    /// The two configurations that build the shipped app. The trailing `;` is load-bearing:
    /// `com.juancasanueva.burnbarTests` starts with the app's identifier too.
    static func appTargetBlocks() throws -> [String] {
        try buildConfigurationBlocks().filter { $0.contains("PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.burnbar;") }
    }

    static func unitTestBlocks() throws -> [String] {
        try buildConfigurationBlocks().filter { $0.contains("PRODUCT_BUNDLE_IDENTIFIER = com.juancasanueva.burnbarTests;") }
    }

    static func appTargetBlocksDeclaring(_ setting: String) throws -> Int {
        try appTargetBlocks().filter { $0.contains(setting) }.count
    }

    /// The body of one `/* Begin … section */ … /* End … section */` pair; empty when absent.
    static func section(_ name: String, in project: String) -> String {
        guard let start = project.range(of: "/* Begin \(name) section */"),
              let end = project.range(of: "/* End \(name) section */"),
              start.upperBound <= end.lowerBound
        else { return "" }
        return String(project[start.upperBound..<end.lowerBound])
    }

    /// Every multi-line object in a section, cut at the two-tab `};` that closes it.
    static func objectBlocks(inSection name: String, of project: String) -> [String] {
        let body = section(name, in: project)
        guard !body.isEmpty else { return [] }
        return Array(body.components(separatedBy: "\n\t\t};").dropLast())
    }

    static func occurrences(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return haystack.components(separatedBy: needle).count - 1
    }
}

@Suite("Project file")
struct ProjectFileTests {
    /// The shipped bundle is `Burnbar.app` in both configurations, and the Swift module keeps the
    /// name every `@testable import burnbar` uses: renaming the product without pinning
    /// `PRODUCT_MODULE_NAME` would silently rename the module.
    @Test func bothAppConfigurationsBuildBurnbarAndKeepTheModuleName() throws {
        #expect(try ProjectSources.appTargetBlocks().count == 2)
        #expect(try ProjectSources.appTargetBlocksDeclaring("PRODUCT_NAME = Burnbar;") == 2)
        #expect(try ProjectSources.appTargetBlocksDeclaring("PRODUCT_MODULE_NAME = burnbar;") == 2)
        #expect(try ProjectSources.appTargetBlocksDeclaring("INFOPLIST_KEY_CFBundleDisplayName = Burnbar;") == 2)
    }

    /// A stale `TEST_HOST` does not fail the build; it fails every test at launch.
    @Test func theUnitTestBundleLoadsTheRenamedHost() throws {
        let blocks = try ProjectSources.unitTestBlocks()
        let host = "TEST_HOST = \"$(BUILT_PRODUCTS_DIR)/Burnbar.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/Burnbar\";"

        #expect(blocks.count == 2)
        #expect(blocks.filter { $0.contains(host) }.count == 2)
        #expect(blocks.filter { $0.contains("BUNDLE_LOADER = \"$(TEST_HOST)\";") }.count == 2)
    }

    /// The running host really is the renamed bundle, with its identifier unchanged.
    @Test func theHostBundleIsBurnbar() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(Bundle.main.bundleURL.lastPathComponent == "Burnbar.app")
        #expect(info["CFBundleIdentifier"] as? String == "com.juancasanueva.burnbar")
        #expect(info["CFBundleName"] as? String == "Burnbar")
        #expect(info["CFBundleDisplayName"] as? String == "Burnbar")
    }
}
