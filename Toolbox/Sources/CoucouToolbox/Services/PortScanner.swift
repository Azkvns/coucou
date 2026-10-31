import Foundation

enum PortScanError: Error {
    case lsofMissing
    case lsofFailed(Int32)
}

protocol PortScanner: Sendable {
    func scan() async throws -> [PortBinding]
}
