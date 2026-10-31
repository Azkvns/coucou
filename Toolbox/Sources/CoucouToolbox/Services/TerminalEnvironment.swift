import Foundation
import SwiftTerm

/// PTY environment for Cyclop terminal sessions.
enum TerminalEnvironment {
    static let markerKey = "CYCLOP_TERMINAL"

    /// Builds the environment passed to `LocalProcess.startProcess`.
    static func build(cols: Int, rows: Int, overrides: [String: String] = [:]) -> [String] {
        var env = keyedEnvironment(from: Terminal.getEnvironmentVariables(termName: "xterm-256color", trueColor: true))
        env["CLICOLOR"] = "1"
        env[markerKey] = "1"
        if cols > 0 { env["COLUMNS"] = String(cols) }
        if rows > 0 { env["LINES"] = String(rows) }
        for (key, value) in overrides {
            env[key] = value
        }
        return env.map { "\($0.key)=\($0.value)" }.sorted()
    }

    static func value(for key: String, in environment: [String]) -> String? {
        keyedEnvironment(from: environment)[key]
    }

    private static func keyedEnvironment(from entries: [String]) -> [String: String] {
        var env: [String: String] = [:]
        for entry in entries {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<separator])
            let value = String(entry[entry.index(after: separator)...])
            env[key] = value
        }
        return env
    }
}
