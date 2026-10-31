import Foundation
import XCTest
@testable import CoucouToolbox

final class TerminalStoreTests: XCTestCase {
    func testTerminalsDocumentRoundTrip() throws {
        let tab = TerminalTab(
            id: UUID(),
            title: "zsh",
            cwd: "/Users/test",
            shell: "/bin/zsh",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let document = TerminalsDocument(tabs: [tab], selectedTabID: tab.id)

        let data = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(TerminalsDocument.self, from: data)

        XCTAssertEqual(decoded, document)
    }

    func testDefaultTabUsesHomeDirectory() {
        let tab = TerminalTab.makeDefault()
        XCTAssertEqual(tab.shell, "/bin/zsh")
        XCTAssertEqual(tab.title, "zsh")
        XCTAssertEqual(tab.cwd, FileManager.default.homeDirectoryForCurrentUser.path)
    }
}
