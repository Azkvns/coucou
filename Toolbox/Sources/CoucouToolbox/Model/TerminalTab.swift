import Foundation

struct TerminalTab: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var cwd: String
    var shell: String
    var createdAt: Date

    static func makeDefault(cwd: String? = nil) -> TerminalTab {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return TerminalTab(
            id: UUID(),
            title: ("/bin/zsh" as NSString).lastPathComponent,
            cwd: cwd ?? home,
            shell: "/bin/zsh",
            createdAt: Date()
        )
    }
}

struct TerminalsDocument: Codable, Equatable {
    var tabs: [TerminalTab]
    var selectedTabID: UUID?

    static let empty = TerminalsDocument(tabs: [], selectedTabID: nil)
}
