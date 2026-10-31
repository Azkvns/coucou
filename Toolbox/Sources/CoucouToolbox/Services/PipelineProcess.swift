import Darwin
import Foundation

@MainActor
final class PipelineProcess {
    private var task: Process?
    private(set) var pid: pid_t?

    static func shellQuote(_ command: String) -> String {
        "'" + command.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Wraps the command so SIGTERM to bash also stops background children.
    private static func wrappedCommand(_ command: String) -> String {
        "trap 'kill 0' TERM; \(command)"
    }

    func run(
        command: String,
        cwd: URL,
        onStdout: @escaping (Data) -> Void,
        onStderr: @escaping (Data) -> Void
    ) async -> Int32 {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        guard FileManager.default.isExecutableFile(atPath: "/bin/bash") else { return 127 }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-lc", Self.wrappedCommand(trimmed)]
        task.currentDirectoryURL = cwd

        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        task.standardInput = FileHandle.nullDevice

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { @MainActor in onStdout(chunk) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { @MainActor in onStderr(chunk) }
        }

        return await withCheckedContinuation { continuation in
            task.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    outPipe.fileHandleForReading.readabilityHandler = nil
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    let remainingOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                    let remainingErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                    if !remainingOut.isEmpty { onStdout(remainingOut) }
                    if !remainingErr.isEmpty { onStderr(remainingErr) }
                    self?.task = nil
                    self?.pid = nil
                    continuation.resume(returning: Int32(process.terminationStatus))
                }
            }

            do {
                try task.run()
                self.task = task
                self.pid = task.processIdentifier
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: 127)
            }
        }
    }

    func terminate(graceful: Bool = true) async {
        guard let pid else { return }
        _ = kill(pid, SIGTERM)
        if graceful {
            try? await Task.sleep(for: .seconds(2))
            if Self.isAlive(pid) {
                _ = kill(pid, SIGKILL)
            }
        } else {
            _ = kill(pid, SIGKILL)
        }
        self.task = nil
        self.pid = nil
    }

    private static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }
}
