import AppKit
import Foundation
import SwiftTerm

/// One pseudo-terminal session. The view lives in the controller so it can be
/// reparented between displays without spawning a second shell.
@MainActor
final class TerminalSessionController: NSObject, @MainActor TerminalViewDelegate, @MainActor LocalProcessDelegate {
    private(set) var tab: TerminalTab
    private(set) var hasExited = false

    var onTitleChange: ((String) -> Void)?
    var onDirectoryChange: ((String) -> Void)?
    var onExit: (() -> Void)?

    private var terminalView: TerminalView?
    private var localProcess: LocalProcess?
    private var spawned = false
    private var pendingCwd: String?

    init(tab: TerminalTab) {
        self.tab = tab
        self.pendingCwd = tab.cwd
        super.init()
    }

    var isRunning: Bool {
        localProcess?.running ?? false
    }

    func updateTab(_ tab: TerminalTab) {
        self.tab = tab
    }

    private func ensureView() -> TerminalView {
        if let terminalView { return terminalView }
        let view = TerminalView(frame: .zero)
        view.terminalDelegate = self
        TerminalAppearance.apply(to: view)
        terminalView = view
        return view
    }

    private func ensureProcess() -> LocalProcess {
        if let localProcess { return localProcess }
        let process = LocalProcess(delegate: self)
        localProcess = process
        return process
    }

    func attach(to container: TerminalContainerView) {
        let view = ensureView()
        if view.superview !== container {
            view.removeFromSuperview()
            container.terminalView = view
            container.addSubview(view)
        }
        view.autoresizingMask = [.width, .height]
        view.frame = container.bounds
        spawnIfNeeded(in: container.bounds)
        if let window = container.window {
            window.makeFirstResponder(view)
        }
    }

    func detach() {
        terminalView?.removeFromSuperview()
    }

    func spawnIfNeeded(in bounds: CGRect) {
        guard !spawned else { return }
        guard bounds.width > 1, bounds.height > 1 else { return }
        let view = ensureView()
        let process = ensureProcess()
        guard !process.running else {
            spawned = true
            return
        }
        view.frame = bounds
        let term = view.getTerminal()
        let environment = TerminalEnvironment.build(
            cols: term.cols,
            rows: term.rows,
            overrides: TerminalShellBootstrap.environmentOverrides()
        )
        process.startProcess(executable: tab.shell, args: ["-il"], environment: environment)
        spawned = true
        if let cwd = pendingCwd, cwd != FileManager.default.homeDirectoryForCurrentUser.path {
            sendLine("cd '\(cwd.shellEscapedPath)'")
        }
        pendingCwd = nil
    }

    func terminate() {
        guard let process = localProcess, process.running else { return }
        process.terminate()
    }

    func captureCWD() -> String? {
        if let dir = tab.cwd.nonEmptyDirectory { return dir }
        guard let pid = localProcess?.shellPid, pid > 0 else { return nil }
        return Self.cwdForPID(pid)
    }

    private func sendLine(_ line: String) {
        guard localProcess?.running == true else { return }
        let bytes = Array(line.utf8) + [UInt8(10)]
        localProcess?.send(data: bytes[...])
    }

    private func windowSize(for view: TerminalView) -> winsize {
        let frame = view.frame
        let term = view.getTerminal()
        return winsize(
            ws_row: UInt16(term.rows),
            ws_col: UInt16(term.cols),
            ws_xpixel: UInt16(frame.width),
            ws_ypixel: UInt16(frame.height)
        )
    }

    // MARK: - TerminalViewDelegate

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        guard localProcess?.running == true, localProcess?.childfd ?? -1 >= 0 else { return }
        var size = windowSize(for: source)
        let fd = localProcess!.childfd
        let _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: fd, windowSize: &size)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tab.title = trimmed
        onTitleChange?(trimmed)
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        tab.cwd = directory
        onDirectoryChange?(directory)
    }

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        localProcess?.send(data: data)
    }

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    func bell(source: TerminalView) {}

    func clipboardCopy(source: TerminalView, content: Data) {
        if let string = String(bytes: content, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([string as NSString])
        }
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

    // MARK: - LocalProcessDelegate

    func dataReceived(slice: ArraySlice<UInt8>) {
        terminalView?.feed(byteArray: slice)
    }

    func getWindowSize() -> winsize {
        guard let view = terminalView else { return winsize() }
        return windowSize(for: view)
    }

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        hasExited = true
        onExit?()
    }

    // MARK: - CWD probe

    nonisolated static func cwdForPID(_ pid: pid_t) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        for line in output.split(separator: "\n") where line.hasPrefix("n") {
            return String(line.dropFirst())
        }
        return nil
    }
}

private extension String {
    var shellEscapedPath: String {
        replacingOccurrences(of: "'", with: "'\\''")
    }

    var nonEmptyDirectory: String? {
        var isDir: ObjCBool = false
        guard !isEmpty, FileManager.default.fileExists(atPath: self, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        return self
    }
}

/// Hosts the shared terminal view for one screen.
final class TerminalContainerView: NSView {
    weak var terminalView: TerminalView?
    var onBoundsChange: ((CGRect) -> Void)?

    override func layout() {
        super.layout()
        terminalView?.frame = bounds
        onBoundsChange?(bounds)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        if let terminalView {
            window?.makeFirstResponder(terminalView)
            return false
        }
        return super.becomeFirstResponder()
    }
}
