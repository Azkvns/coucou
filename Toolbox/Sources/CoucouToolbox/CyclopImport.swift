import AppKit
import Foundation

/// Decode everything before changing the destination; source files are never written.
struct CyclopImport {
    let pipelines: [Pipeline]
    let terminals: [TerminalTab]

    static func validateDestination(_ directory: URL) throws {
        let fm = FileManager.default
        let pipelines = directory.appendingPathComponent("pipelines.json")
        let terminals = directory.appendingPathComponent("terminals.json")
        if fm.fileExists(atPath: pipelines.path) {
            _ = try JSONDecoder().decode(PipelinesDocument.self, from: Data(contentsOf: pipelines))
        }
        if fm.fileExists(atPath: terminals.path) {
            _ = try JSONDecoder().decode(TerminalsDocument.self, from: Data(contentsOf: terminals))
        }
    }

    init(directory: URL) throws {
        let fm = FileManager.default
        let p = directory.appendingPathComponent("pipelines.json")
        let t = directory.appendingPathComponent("terminals.json")
        pipelines = fm.fileExists(atPath: p.path)
            ? try JSONDecoder().decode(PipelinesDocument.self, from: Data(contentsOf: p)).pipelines : []
        terminals = fm.fileExists(atPath: t.path)
            ? try JSONDecoder().decode(TerminalsDocument.self, from: Data(contentsOf: t)).tabs : []
        guard terminals.allSatisfy({ $0.shell.hasPrefix("/") && $0.cwd.hasPrefix("/") }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }
}
