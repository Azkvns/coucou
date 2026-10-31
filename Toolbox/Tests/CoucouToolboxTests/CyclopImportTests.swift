import Foundation
import XCTest
@testable import CoucouToolbox

final class CyclopImportTests: XCTestCase {
    func testImportDecodesSavedConfigurationWithoutChangingSource() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tab = TerminalTab.makeDefault(cwd: "/tmp")
        let bytes = try JSONEncoder().encode(TerminalsDocument(tabs: [tab], selectedTabID: tab.id))
        let file = folder.appendingPathComponent("terminals.json")
        try bytes.write(to: file)
        let imported = try CyclopImport(directory: folder)
        XCTAssertEqual(imported.terminals, [tab])
        XCTAssertTrue(imported.pipelines.isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testInvalidFileFailsBeforeImport() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("broken json".utf8).write(to: folder.appendingPathComponent("pipelines.json"))
        XCTAssertThrowsError(try CyclopImport(directory: folder))
        XCTAssertThrowsError(try CyclopImport.validateDestination(folder))
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("pipelines.json"), encoding: .utf8), "broken json")
    }

    func testRelativeShellIsRejected() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var tab = TerminalTab.makeDefault(cwd: "/tmp")
        tab.shell = "untrusted-relative-command"
        try JSONEncoder().encode(TerminalsDocument(tabs: [tab], selectedTabID: tab.id))
            .write(to: folder.appendingPathComponent("terminals.json"))
        XCTAssertThrowsError(try CyclopImport(directory: folder))
    }
}
