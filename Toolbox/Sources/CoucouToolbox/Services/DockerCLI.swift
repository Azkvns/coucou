import Foundation
import Darwin

enum DockerAction: String, Equatable, Sendable {
    case start
    case restart
    case kill
}

enum DockerCLICommand: Equatable, Sendable {
    case inspect
    case action(DockerAction)
}

enum DockerCLIError: Error, Equatable, Sendable {
    case dockerNotFound
    case dockerNotRunning
    case commandFailed(String)
}

struct DockerInspectExit: Error, Equatable, Sendable, ExpressibleByIntegerLiteral {
    let code: Int

    init(_ code: Int) {
        self.code = code
    }

    init(integerLiteral value: Int) {
        code = value
    }
}

protocol DockerExecuting: Sendable {
    func snapshots(for specs: [DockerServiceSpec]) async -> Result<[DockerServiceSnapshot], DockerCLIError>
    func perform(_ action: DockerAction, name: String) async -> Result<Void, DockerCLIError>
}

struct DockerCLI: DockerExecuting {
    func snapshots(for specs: [DockerServiceSpec]) async -> Result<[DockerServiceSnapshot], DockerCLIError> {
        guard let binary = Self.findBinary() else {
            return .failure(.dockerNotFound)
        }

        var inspectResults: [String: Result<Data, DockerInspectExit>] = [:]
        var health: [String: DockerHTTPHealth] = [:]

        for spec in specs {
            let command = await Self.run(
                executable: binary,
                arguments: Self.arguments(for: .inspect, name: spec.name),
                timeout: 30
            )

            if Self.isDaemonUnavailable(command.stderr) {
                return .failure(.dockerNotRunning)
            }
            if command.timedOut {
                return .failure(.commandFailed("docker inspect timed out"))
            }

            if command.exitCode == 0 {
                inspectResults[spec.name] = .success(command.stdout)
            } else if command.exitCode == 1, Self.isMissingContainer(command.stderr) {
                inspectResults[spec.name] = .failure(DockerInspectExit(1))
            } else {
                return .failure(.commandFailed(Self.errorMessage(
                    command.stderr,
                    fallback: "docker inspect \(spec.name) exited \(command.exitCode)"
                )))
            }

            if command.exitCode == 0, spec.healthURL != nil {
                health[spec.name] = await DockerHealthClient.probe(urlString: spec.healthURL)
            }
        }

        return Self.merge(inspectResults: inspectResults, health: health, specs: specs)
    }

    func perform(_ action: DockerAction, name: String) async -> Result<Void, DockerCLIError> {
        guard let binary = Self.findBinary() else {
            return .failure(.dockerNotFound)
        }

        let command = await Self.run(
            executable: binary,
            arguments: Self.arguments(for: .action(action), name: name),
            timeout: Self.timeout(for: action)
        )

        if Self.isDaemonUnavailable(command.stderr) {
            return .failure(.dockerNotRunning)
        }
        if command.timedOut {
            return .failure(.commandFailed("docker \(action.rawValue) timed out"))
        }
        guard command.exitCode == 0 else {
            return .failure(.commandFailed(Self.errorMessage(
                command.stderr,
                fallback: "docker \(action.rawValue) exited \(command.exitCode)"
            )))
        }
        return .success(())
    }

    static func arguments(for command: DockerCLICommand, name: String) -> [String] {
        switch command {
        case .inspect:
            return ["inspect", "--size", "--type", "container", "--", name]
        case .action(let action):
            return [action.rawValue, "--", name]
        }
    }

    static func findBinary() -> String? {
        let paths = [
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            "/usr/bin/docker",
            "/Applications/Docker.app/Contents/Resources/bin/docker",
        ]
        for path in paths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        let which = runSync(executable: "/usr/bin/which", arguments: ["docker"])
        guard which.exitCode == 0,
              let path = String(data: which.stdout, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty,
              FileManager.default.isExecutableFile(atPath: path) else {
            return nil
        }
        return path
    }

    static func merge(
        inspectResults: [String: Result<Data, DockerInspectExit>],
        health: [String: DockerHTTPHealth],
        specs: [DockerServiceSpec]
    ) -> Result<[DockerServiceSnapshot], DockerCLIError> {
        var snapshots: [DockerServiceSnapshot] = []

        for spec in specs {
            guard let inspectResult = inspectResults[spec.name] else {
                return .failure(.commandFailed("missing inspect result for \(spec.name)"))
            }

            switch inspectResult {
            case .success(let data):
                do {
                    var snapshot = try DockerInspectParser.parse(data, spec: spec)
                    snapshot.httpHealth = health[spec.name] ?? .none
                    snapshots.append(snapshot)
                } catch {
                    return .failure(.commandFailed("invalid inspect response for \(spec.name)"))
                }
            case .failure(let exit):
                guard exit.code == 1 else {
                    return .failure(.commandFailed("docker inspect \(spec.name) exited \(exit.code)"))
                }
                snapshots.append(
                    DockerServiceSnapshot(
                        spec: spec,
                        runtime: .missing,
                        healthcheck: .none,
                        httpHealth: .none,
                        ports: [],
                        sizeBytes: nil,
                        error: nil
                    )
                )
            }
        }

        return .success(snapshots)
    }

    private struct CommandResult {
        var stdout: Data
        var stderr: Data
        var exitCode: Int32
        var timedOut: Bool
    }

    private static func timeout(for action: DockerAction) -> TimeInterval {
        switch action {
        case .start, .restart: return 30
        case .kill: return 10
        }
    }

    private static func isDaemonUnavailable(_ data: Data) -> Bool {
        let message = String(data: data, encoding: .utf8)?.lowercased() ?? ""
        return message.contains("cannot connect to the docker daemon")
            || message.contains("is the docker daemon running")
            || message.contains("error during connect")
            || message.contains("docker daemon is not running")
    }

    private static func isMissingContainer(_ data: Data) -> Bool {
        let message = String(data: data, encoding: .utf8)?.lowercased() ?? ""
        return message.contains("no such object")
            || message.contains("no such container")
    }

    private static func errorMessage(_ data: Data, fallback: String) -> String {
        let message = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return message.isEmpty ? fallback : message
    }

    private static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) async -> CommandResult {
        await Task.detached(priority: .utility) {
            runSync(executable: executable, arguments: arguments, timeout: timeout)
        }.value
    }

    private static func runSync(
        executable: String,
        arguments: [String],
        timeout: TimeInterval? = nil
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return CommandResult(
                stdout: Data(),
                stderr: Data(error.localizedDescription.utf8),
                exitCode: -1,
                timedOut: false
            )
        }

        var timedOut = false
        if let timeout {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                timedOut = true
                process.terminate()
                let terminationDeadline = Date().addingTimeInterval(1)
                while process.isRunning && Date() < terminationDeadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
                process.waitUntilExit()
            }
        } else {
            process.waitUntilExit()
        }

        return CommandResult(
            stdout: stdout.fileHandleForReading.readDataToEndOfFile(),
            stderr: stderr.fileHandleForReading.readDataToEndOfFile(),
            exitCode: process.terminationStatus,
            timedOut: timedOut
        )
    }
}
