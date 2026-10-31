import Foundation
import XCTest
@testable import CoucouToolbox

final class LsofPortScannerTests: XCTestCase {
    func testParseTCPListenBinding() {
        let fixture = """
        p12345
        cnode
        f5
        PTCP
        n*:8080
        TST=LISTEN
        """

        let bindings = LsofPortScanner.parse(Data(fixture.utf8))

        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].pid, 12345)
        XCTAssertEqual(bindings[0].processName, "node")
        XCTAssertEqual(bindings[0].port, 8080)
        XCTAssertEqual(bindings[0].proto, "TCP")
        XCTAssertEqual(bindings[0].state, "LISTEN")
        XCTAssertEqual(bindings[0].address, "*")
        XCTAssertEqual(bindings[0].kind, .tcpListen)
    }

    func testParseUDPSocket() {
        let fixture = """
        p999
        cdns
        f3
        PUDP
        n127.0.0.1:5353
        """

        let bindings = LsofPortScanner.parse(Data(fixture.utf8))

        XCTAssertEqual(bindings.count, 1)
        XCTAssertEqual(bindings[0].proto, "UDP")
        XCTAssertEqual(bindings[0].state, "UDP")
        XCTAssertEqual(bindings[0].port, 5353)
        XCTAssertEqual(bindings[0].kind, .udp)
    }

    func testParseDoesNotSortByPort() {
        let fixture = """
        p1
        cz
        f1
        PTCP
        n*:9000
        TST=LISTEN
        p2
        ca
        f2
        PTCP
        n*:8080
        TST=LISTEN
        """

        let bindings = LsofPortScanner.parse(Data(fixture.utf8))

        XCTAssertEqual(bindings.map(\.port), [9000, 8080])
    }
}

@MainActor
final class PortStoreTests: XCTestCase {
    func testMergePreservesFirstSeenAt() {
        let store = PortStore(scanner: StubPortScanner(bindings: []))
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let t1 = Date(timeIntervalSince1970: 1_700_000_100)

        let first = makeBinding(id: "a", port: 8080, firstSeenAt: .distantPast)
        let mergedOnce = store.mergeForTesting([first], at: t0)
        XCTAssertEqual(mergedOnce[0].firstSeenAt, t0)

        let mergedTwice = store.mergeForTesting([first], at: t1)
        XCTAssertEqual(mergedTwice[0].firstSeenAt, t0)
    }

    func testSortNewestFirst() {
        let store = PortStore(scanner: StubPortScanner(bindings: []))
        store.sortOrder = .newestFirst
        let older = makeBinding(id: "old", port: 8080, firstSeenAt: Date(timeIntervalSince1970: 100))
        let newer = makeBinding(id: "new", port: 9090, firstSeenAt: Date(timeIntervalSince1970: 200))
        store.setBindingsForTesting([older, newer])

        XCTAssertEqual(store.displayedBindings.map(\.id), ["new", "old"])
    }

    func testSortPortNumber() {
        let store = PortStore(scanner: StubPortScanner(bindings: []))
        store.sortOrder = .portNumber
        store.setBindingsForTesting([
            makeBinding(id: "b", port: 9090, processName: "b"),
            makeBinding(id: "a", port: 8080, processName: "a"),
        ])

        XCTAssertEqual(store.displayedBindings.map(\.port), [8080, 9090])
    }
}

private struct StubPortScanner: PortScanner {
    let bindings: [PortBinding]

    func scan() async throws -> [PortBinding] {
        bindings
    }
}

private func makeBinding(
    id: String,
    port: Int,
    processName: String = "node",
    proto: String = "TCP",
    state: String = "LISTEN",
    firstSeenAt: Date = .distantPast,
    processStartedAt: Date? = nil
) -> PortBinding {
    PortBinding(
        id: id,
        pid: 1,
        uid: 501,
        port: port,
        proto: proto,
        address: "*",
        state: state,
        processName: processName,
        executablePath: nil,
        commandLine: nil,
        firstSeenAt: firstSeenAt,
        processStartedAt: processStartedAt
    )
}
