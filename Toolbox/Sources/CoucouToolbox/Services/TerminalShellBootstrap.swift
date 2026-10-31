import Foundation

/// Prepares zsh startup files and ZDOTDIR for Cyclop terminal sessions.
enum TerminalShellBootstrap {
    private static let resourceName = "cyclop-zshrc"
    private static let resourceDirectory = "terminal"
    private static let zdotdirName = "terminal"

    /// Known install locations for `zsh-syntax-highlighting` (for tests and docs).
    static let syntaxHighlightingCandidates: [String] = [
        "/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh",
        "/usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh",
    ]

    /// Directory that contains `.zshrc` for `ZDOTDIR`.
    static func zdotDirectory() -> URL {
        let dir = Support.directory(zdotdirName)
        ensureZshrc(in: dir)
        return dir
    }

    /// Environment overrides for shell spawn.
    static func environmentOverrides() -> [String: String] {
        ["ZDOTDIR": zdotDirectory().path]
    }

    /// Returns the first known syntax-highlighting path that exists on disk.
    static func installedSyntaxHighlightingPath(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        firstExistingPath(in: syntaxHighlightingSearchPaths(environment: environment), fileManager: fileManager)
    }

    static func syntaxHighlightingSearchPaths(environment: [String: String]) -> [String] {
        var candidates = syntaxHighlightingCandidates
        if let zsh = environment["ZSH"], !zsh.isEmpty {
            candidates.append("\(zsh)/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh")
            candidates.append("\(zsh)/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh")
        }
        return candidates
    }

    static func firstExistingPath(in paths: [String], fileManager: FileManager = .default) -> String? {
        paths.first { fileManager.fileExists(atPath: $0) }
    }

    private static func ensureZshrc(in directory: URL) {
        let destination = directory.appendingPathComponent(".zshrc")
        guard let source = bundledBootstrapURL() else {
            writeEmbeddedBootstrap(to: destination)
            return
        }
        let fm = FileManager.default
        if !fm.fileExists(atPath: destination.path) {
            try? fm.copyItem(at: source, to: destination)
            return
        }
        guard
            let sourceData = try? Data(contentsOf: source),
            let destinationData = try? Data(contentsOf: destination),
            sourceData != destinationData
        else { return }
        try? fm.removeItem(at: destination)
        try? fm.copyItem(at: source, to: destination)
    }

    private static func bundledBootstrapURL() -> URL? {
        if let url = Bundle.main.url(forResource: resourceName, withExtension: nil, subdirectory: resourceDirectory) {
            return url
        }
        if let path = Bundle.main.path(forResource: resourceName, ofType: nil, inDirectory: resourceDirectory) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private static func writeEmbeddedBootstrap(to destination: URL) {
        let content = """
        # Cyclop terminal bootstrap. Loaded via ZDOTDIR; sources the user's ~/.zshrc first.

        if [[ -f "$HOME/.zshrc" ]]; then
          source "$HOME/.zshrc"
        fi

        if (( ! ${+functions[_zsh_highlight]} )); then
          for _cyclop_zsh_highlight in \\
            "/opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \\
            "/usr/local/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \\
            "${ZSH:+$ZSH/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh}" \\
            "${ZSH:+$ZSH/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh}"
          do
            [[ -n "$_cyclop_zsh_highlight" && -f "$_cyclop_zsh_highlight" ]] || continue
            source "$_cyclop_zsh_highlight"
            break
          done
          unset _cyclop_zsh_highlight
        fi
        """
        try? content.write(to: destination, atomically: true, encoding: .utf8)
    }
}
