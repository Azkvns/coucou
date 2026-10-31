import Foundation

enum PortKind: Sendable, Hashable {
    case tcpListen
    case tcpEstablished
    case udp
    case other

    init(binding: PortBinding) {
        if binding.proto == "UDP" || binding.state == "UDP" {
            self = .udp
        } else if binding.isListening {
            self = .tcpListen
        } else if binding.isEstablished {
            self = .tcpEstablished
        } else {
            self = .other
        }
    }
}

enum PortSortOrder: String, CaseIterable, Sendable {
    case newestFirst
    case oldestFirst
    case portNumber
    case processName
}

enum PortProtoFilter: String, CaseIterable, Sendable {
    case all
    case tcp
    case udp
}

struct PortBinding: Identifiable, Hashable, Sendable {
    let id: String
    let pid: pid_t
    let uid: uid_t
    let port: Int
    let proto: String
    let address: String
    let state: String
    let processName: String
    let executablePath: String?
    let commandLine: String?
    let firstSeenAt: Date
    let processStartedAt: Date?

    var isListening: Bool { state.uppercased() == "LISTEN" }
    var isEstablished: Bool { state.uppercased() == "ESTABLISHED" }
    var kind: PortKind { PortKind(binding: self) }

    func withTimestamps(firstSeenAt: Date, processStartedAt: Date?) -> PortBinding {
        PortBinding(
            id: id,
            pid: pid,
            uid: uid,
            port: port,
            proto: proto,
            address: address,
            state: state,
            processName: processName,
            executablePath: executablePath,
            commandLine: commandLine,
            firstSeenAt: firstSeenAt,
            processStartedAt: processStartedAt
        )
    }
}

enum PortOwnerFilter: String, CaseIterable {
    case mine, all
}

enum PortStateFilter: String, CaseIterable {
    case listen, established, all
}
