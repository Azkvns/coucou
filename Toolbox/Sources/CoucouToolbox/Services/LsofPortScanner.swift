import Foundation

struct LsofPortScanner: PortScanner {
    private static let lsofPath = "/usr/sbin/lsof"

    func scan() async throws -> [PortBinding] {
        try await Task.detached(priority: .utility) {
            guard FileManager.default.isExecutableFile(atPath: Self.lsofPath) else {
                throw PortScanError.lsofMissing
            }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: Self.lsofPath)
            task.arguments = ["-nP", "-iTCP", "-iUDP", "-F", "pcnPT"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()

            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let bindings = Self.parse(data)

            if bindings.isEmpty, task.terminationStatus == 2 {
                throw PortScanError.lsofFailed(task.terminationStatus)
            }

            return bindings
        }.value
    }

    static func parse(_ data: Data) -> [PortBinding] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        struct ProcessInfo {
            var uid: uid_t?
            var path: String?
            var commandLine: String?
            var startedAt: Date?
        }

        var bindings: [PortBinding] = []
        var pid: pid_t?
        var command: String?
        var proto: String?
        var network: String?
        var state = "UNKNOWN"
        var processCache: [pid_t: ProcessInfo] = [:]

        func cachedProcessInfo(for pid: pid_t) -> ProcessInfo {
            if let cached = processCache[pid] { return cached }
            let info = ProcessInfo(
                uid: ProcessLookup.uid(for: pid),
                path: ProcessLookup.path(for: pid),
                commandLine: ProcessLookup.commandLine(for: pid),
                startedAt: ProcessLookup.startedAt(for: pid)
            )
            processCache[pid] = info
            return info
        }

        func flushFD() {
            guard let pid, let command, let currentProto = proto, let currentNetwork = network,
                  let parsed = parseNetworkLine(currentNetwork, proto: currentProto, state: state) else {
                proto = nil
                network = nil
                state = "UNKNOWN"
                return
            }

            let info = cachedProcessInfo(for: pid)
            let uid = info.uid ?? uid_t.max
            let id = "\(pid)-\(parsed.proto)-\(parsed.port)-\(parsed.address)-\(parsed.state)"
            let binding = PortBinding(
                id: id,
                pid: pid,
                uid: uid,
                port: parsed.port,
                proto: parsed.proto,
                address: parsed.address,
                state: parsed.state,
                processName: command,
                executablePath: info.path,
                commandLine: info.commandLine,
                firstSeenAt: .distantPast,
                processStartedAt: info.startedAt
            )
            if !bindings.contains(where: { $0.id == binding.id }) {
                bindings.append(binding)
            }
            proto = nil
            network = nil
            state = "UNKNOWN"
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            guard let marker = line.first else { continue }
            let value = String(line.dropFirst())

            switch marker {
            case "p":
                flushFD()
                pid = pid_t(value)
                command = nil
            case "c":
                command = value
            case "f":
                flushFD()
            case "P":
                proto = value.uppercased()
            case "n":
                network = value
            case "T":
                if value.hasPrefix("ST=") {
                    state = String(value.dropFirst(3)).uppercased()
                }
            default:
                continue
            }
        }
        flushFD()

        return bindings
    }

    private struct ParsedNetwork {
        let proto: String
        let address: String
        let port: Int
        let state: String
    }

    private static func parseNetworkLine(_ line: String, proto: String, state: String) -> ParsedNetwork? {
        let local = line.split(separator: "->", maxSplits: 1).first.map(String.init) ?? line
        guard let port = parsePort(from: local) else { return nil }

        let address: String
        if let range = local.range(of: "]:") {
            address = String(local[..<range.upperBound])
        } else if let colon = local.lastIndex(of: ":") {
            address = String(local[..<colon])
        } else {
            address = local
        }

        let normalizedState: String
        if state != "UNKNOWN" {
            normalizedState = state
        } else if proto == "UDP" {
            normalizedState = "UDP"
        } else {
            normalizedState = state
        }

        return ParsedNetwork(proto: proto, address: address, port: port, state: normalizedState)
    }

    private static func parsePort(from endpoint: String) -> Int? {
        if let range = endpoint.range(of: "]:") {
            return Int(endpoint[range.upperBound...])
        }
        guard let colon = endpoint.lastIndex(of: ":") else { return nil }
        let portString = String(endpoint[endpoint.index(after: colon)...])
        guard let port = Int(portString) else { return nil }
        return port
    }
}
