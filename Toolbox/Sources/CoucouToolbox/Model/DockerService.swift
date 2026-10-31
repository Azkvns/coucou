import Foundation

struct DockerServiceSpec: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var name: String
    var healthURL: String?
}

enum DockerRuntimeState: String, Equatable, Sendable {
    case running, exited, restarting, paused, created, dead, missing
}

enum DockerHealthcheck: String, Equatable, Sendable {
    case none, starting, healthy, unhealthy
}

enum DockerHTTPHealth: String, Equatable, Sendable {
    case none, up, degraded, down
}

struct DockerPublishedPort: Equatable, Sendable, Identifiable {
    var id: String { "\(hostIP):\(hostPort)/\(proto)" }
    var hostIP: String
    var hostPort: String
    var proto: String
}

struct DockerServiceSnapshot: Equatable, Sendable {
    var spec: DockerServiceSpec
    var runtime: DockerRuntimeState
    var healthcheck: DockerHealthcheck
    var httpHealth: DockerHTTPHealth
    var ports: [DockerPublishedPort]
    var sizeBytes: Int64?
    var error: String?
}

enum DockerServiceChange: Equatable {
    case runtime(DockerRuntimeState)
    case healthcheck(DockerHealthcheck)
    case httpHealth(DockerHTTPHealth)
}

enum DockerInspectParserError: Error {
    case invalidPayload
}

enum DockerInspectParser {
    static func parse(_ data: Data, spec: DockerServiceSpec) throws -> DockerServiceSnapshot {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let inspect = array.first else {
            throw DockerInspectParserError.invalidPayload
        }

        let state = inspect["State"] as? [String: Any]
        let runtime = runtimeState(from: state?["Status"] as? String)
        let healthcheck = healthcheck(from: state)
        let sizeBytes = (inspect["SizeRootFs"] as? NSNumber)?.int64Value
        let ports = publishedPorts(from: inspect)

        return DockerServiceSnapshot(
            spec: spec,
            runtime: runtime,
            healthcheck: healthcheck,
            httpHealth: .none,
            ports: ports,
            sizeBytes: sizeBytes,
            error: nil
        )
    }

    static func classifyHTTP(statusCode: Int, body: Data?) -> DockerHTTPHealth {
        guard (200...299).contains(statusCode) else {
            return .down
        }

        if let body, !body.isEmpty,
           let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            if json["state"] as? String == "degraded" || json["status"] as? String == "degraded" {
                return .degraded
            }
        }

        return .up
    }

    static func publishedPorts(from inspect: [String: Any]) -> [DockerPublishedPort] {
        guard let networkSettings = inspect["NetworkSettings"] as? [String: Any],
              let portsDict = networkSettings["Ports"] as? [String: Any] else {
            return []
        }

        var ports: [DockerPublishedPort] = []
        for (key, value) in portsDict {
            let parts = key.split(separator: "/")
            guard parts.count == 2 else { continue }
            let proto = String(parts[1])

            guard let bindings = value as? [[String: Any]] else { continue }
            for binding in bindings {
                guard let hostIP = binding["HostIp"] as? String,
                      let hostPort = binding["HostPort"] as? String else {
                    continue
                }
                ports.append(DockerPublishedPort(hostIP: hostIP, hostPort: hostPort, proto: proto))
            }
        }
        return ports.sorted {
            ($0.hostIP, $0.hostPort, $0.proto) < ($1.hostIP, $1.hostPort, $1.proto)
        }
    }

    private static func runtimeState(from status: String?) -> DockerRuntimeState {
        switch status?.lowercased() {
        case "running": return .running
        case "exited": return .exited
        case "restarting": return .restarting
        case "paused": return .paused
        case "created": return .created
        case "dead": return .dead
        default: return .exited
        }
    }

    private static func healthcheck(from state: [String: Any]?) -> DockerHealthcheck {
        guard let health = state?["Health"] as? [String: Any],
              let status = health["Status"] as? String else {
            return .none
        }

        switch status.lowercased() {
        case "starting": return .starting
        case "healthy": return .healthy
        case "unhealthy": return .unhealthy
        default: return .none
        }
    }
}

enum DockerBannerCopy {
    static func message(name: String, change: DockerServiceChange) -> String? {
        switch change {
        case .runtime(.running):
            return localized("%@ started", name)
        case .runtime(.exited):
            return localized("%@ stopped", name)
        case .healthcheck(.unhealthy):
            return localized("%@ is unhealthy", name)
        case .healthcheck(.healthy):
            return localized("%@ is healthy", name)
        case .httpHealth(.down):
            return localized("%@ health is down", name)
        case .httpHealth(.up):
            return localized("%@ health is up", name)
        case .runtime, .healthcheck, .httpHealth:
            return nil
        }
    }
}

enum DockerSnapshotDiff {
    static func changes(from previous: DockerServiceSnapshot, to current: DockerServiceSnapshot) -> [DockerServiceChange] {
        var changes: [DockerServiceChange] = []
        if previous.runtime != current.runtime {
            changes.append(.runtime(current.runtime))
        }
        if previous.healthcheck != current.healthcheck {
            changes.append(.healthcheck(current.healthcheck))
        }
        if previous.httpHealth != current.httpHealth {
            changes.append(.httpHealth(current.httpHealth))
        }
        return changes
    }
}
