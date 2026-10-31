import XCTest
@testable import CoucouToolbox

final class TerminalAppearanceTests: XCTestCase {
    func testPaletteHasSixteenColors() {
        XCTAssertEqual(TerminalAppearance.palette().count, 16)
    }
}

final class TerminalEnvironmentTests: XCTestCase {
    func testBuildIncludesColorKeys() {
        let env = TerminalEnvironment.build(cols: 80, rows: 24)
        XCTAssertEqual(TerminalEnvironment.value(for: "TERM", in: env), "xterm-256color")
        XCTAssertEqual(TerminalEnvironment.value(for: "COLORTERM", in: env), "truecolor")
        XCTAssertEqual(TerminalEnvironment.value(for: "CLICOLOR", in: env), "1")
        XCTAssertEqual(TerminalEnvironment.value(for: TerminalEnvironment.markerKey, in: env), "1")
    }

    func testBuildIncludesTerminalDimensions() {
        let env = TerminalEnvironment.build(cols: 120, rows: 40)
        XCTAssertEqual(TerminalEnvironment.value(for: "COLUMNS", in: env), "120")
        XCTAssertEqual(TerminalEnvironment.value(for: "LINES", in: env), "40")
    }

    func testBuildAppliesOverrides() {
        let env = TerminalEnvironment.build(cols: 80, rows: 24, overrides: ["ZDOTDIR": "/tmp/cyclop-terminal"])
        XCTAssertEqual(TerminalEnvironment.value(for: "ZDOTDIR", in: env), "/tmp/cyclop-terminal")
    }
}

final class TerminalShellBootstrapTests: XCTestCase {
    func testSyntaxHighlightingCandidatesAreNonEmpty() {
        XCTAssertFalse(TerminalShellBootstrap.syntaxHighlightingCandidates.isEmpty)
    }

    func testInstalledSyntaxHighlightingPathFindsExistingFile() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pluginDir = directory
            .appendingPathComponent("plugins/zsh-syntax-highlighting", isDirectory: true)
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        let plugin = pluginDir.appendingPathComponent("zsh-syntax-highlighting.zsh")
        try "echo test".write(to: plugin, atomically: true, encoding: .utf8)

        let paths = [
            "\(directory.path)/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh",
            "\(directory.path)/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh",
        ]
        let found = TerminalShellBootstrap.firstExistingPath(in: paths)
        XCTAssertEqual(found, plugin.path)
    }

    func testZdotDirectoryCreatesZshrc() {
        let dir = TerminalShellBootstrap.zdotDirectory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(".zshrc").path))
    }

    func testEnvironmentOverridesIncludeZdotdir() {
        let overrides = TerminalShellBootstrap.environmentOverrides()
        XCTAssertNotNil(overrides["ZDOTDIR"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: overrides["ZDOTDIR"]!))
    }
}
