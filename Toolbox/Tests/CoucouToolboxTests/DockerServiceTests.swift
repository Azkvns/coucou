import Foundation
import XCTest
@testable import CoucouToolbox

final class DockerServiceTests: XCTestCase {
    private let spec = DockerServiceSpec(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "gitlab-digest",
        healthURL: "http://127.0.0.1:8787/health"
    )

    private let inspectFixture = """
    [
      {
        "State": {
          "Status": "running",
          "Health": {
            "Status": "healthy"
          }
        },
        "SizeRootFs": 83886080,
        "NetworkSettings": {
          "Ports": {
            "8787/tcp": [
              {
                "HostIp": "127.0.0.1",
                "HostPort": "8787"
              }
            ]
          }
        }
      }
    ]
    """

    func testParseInspectFixture() throws {
        let snapshot = try DockerInspectParser.parse(Data(inspectFixture.utf8), spec: spec)

        XCTAssertEqual(snapshot.runtime, .running)
        XCTAssertEqual(snapshot.healthcheck, .healthy)
        XCTAssertEqual(snapshot.sizeBytes, 83_886_080)
        XCTAssertEqual(snapshot.ports.count, 1)
        XCTAssertEqual(snapshot.ports[0].hostIP, "127.0.0.1")
        XCTAssertEqual(snapshot.ports[0].hostPort, "8787")
        XCTAssertEqual(snapshot.ports[0].proto, "tcp")
        XCTAssertEqual(snapshot.spec.name, "gitlab-digest")
    }

    func testParseWithoutHealthReturnsNone() throws {
        let json = """
        [
          {
            "State": { "Status": "running" },
            "NetworkSettings": { "Ports": {} }
          }
        ]
        """

        let snapshot = try DockerInspectParser.parse(Data(json.utf8), spec: spec)

        XCTAssertEqual(snapshot.healthcheck, .none)
    }

    func testParseUnknownRuntimeStatusDefaultsToExited() throws {
        let json = """
        [
          {
            "State": { "Status": "weird-state" },
            "NetworkSettings": { "Ports": {} }
          }
        ]
        """

        let snapshot = try DockerInspectParser.parse(Data(json.utf8), spec: spec)

        XCTAssertEqual(snapshot.runtime, .exited)
    }

    func testClassifyHTTPDegradedFromStateField() {
        let body = Data(#"{"state":"degraded"}"#.utf8)
        XCTAssertEqual(DockerInspectParser.classifyHTTP(statusCode: 200, body: body), .degraded)
    }

    func testClassifyHTTPDegradedFromStatusField() {
        let body = Data(#"{"status":"degraded"}"#.utf8)
        XCTAssertEqual(DockerInspectParser.classifyHTTP(statusCode: 200, body: body), .degraded)
    }

    func testClassifyHTTPUpOn2xxWithoutDegradedBody() {
        XCTAssertEqual(DockerInspectParser.classifyHTTP(statusCode: 200, body: nil), .up)
    }

    func testClassifyHTTPDownOnNon2xx() {
        XCTAssertEqual(DockerInspectParser.classifyHTTP(statusCode: 503, body: nil), .down)
    }

    func testDockerCLIMergeKeepsRunningSnapshotWhenAnotherContainerIsMissing() throws {
        let missingSpec = DockerServiceSpec(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "missing-service",
            healthURL: nil
        )

        let result = DockerCLI.merge(
            inspectResults: [
                spec.name: .success(Data(inspectFixture.utf8)),
                missingSpec.name: .failure(1),
            ],
            health: [spec.name: .up],
            specs: [missingSpec, spec]
        )

        let snapshots = try result.get()
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0].spec, missingSpec)
        XCTAssertEqual(snapshots[0].runtime, .missing)
        XCTAssertEqual(snapshots[0].httpHealth, .none)
        XCTAssertEqual(snapshots[1].spec, spec)
        XCTAssertEqual(snapshots[1].runtime, .running)
        XCTAssertEqual(snapshots[1].httpHealth, .up)
    }

    func testSnapshotDiffIgnoresPortsAndSize() {
        let previous = makeSnapshot(
            runtime: .running,
            healthcheck: .healthy,
            httpHealth: .up,
            ports: [DockerPublishedPort(hostIP: "127.0.0.1", hostPort: "8787", proto: "tcp")],
            sizeBytes: 100
        )
        let current = makeSnapshot(
            runtime: .running,
            healthcheck: .healthy,
            httpHealth: .up,
            ports: [DockerPublishedPort(hostIP: "0.0.0.0", hostPort: "9090", proto: "tcp")],
            sizeBytes: 999_999
        )

        XCTAssertTrue(DockerSnapshotDiff.changes(from: previous, to: current).isEmpty)
    }

    func testSnapshotDiffDetectsRuntimeChange() {
        let previous = makeSnapshot(runtime: .running)
        let current = makeSnapshot(runtime: .exited)

        let changes = DockerSnapshotDiff.changes(from: previous, to: current)

        XCTAssertEqual(changes, [.runtime(.exited)])
    }

    func testSnapshotDiffDetectsHealthcheckChange() {
        let previous = makeSnapshot(healthcheck: .healthy)
        let current = makeSnapshot(healthcheck: .unhealthy)

        let changes = DockerSnapshotDiff.changes(from: previous, to: current)

        XCTAssertEqual(changes, [.healthcheck(.unhealthy)])
    }

    func testSnapshotDiffDetectsHTTPHealthChange() {
        let previous = makeSnapshot(httpHealth: .up)
        let current = makeSnapshot(httpHealth: .down)

        let changes = DockerSnapshotDiff.changes(from: previous, to: current)

        XCTAssertEqual(changes, [.httpHealth(.down)])
    }

    func testDockerRuntimeNotificationUsesDockerSourceAndDedupeKey() {
        let notification = NotchNotification.docker(
            name: spec.name,
            change: .runtime(.exited)
        )

        XCTAssertEqual(notification?.source, .docker)
        XCTAssertEqual(notification?.dedupeKey, "docker.gitlab-digest.runtime.exited")
        XCTAssertEqual(notification?.symbol, "stop.fill")
        XCTAssertEqual(notification?.accent.style, .warning)
        XCTAssertEqual(notification?.message, localized("%@ stopped", spec.name))
        XCTAssertFalse(notification?.message.contains("docker.banner") ?? true)
    }

    func testDockerHealthNotificationUsesChangeSpecificDedupeKey() {
        let notification = NotchNotification.docker(
            name: spec.name,
            change: .healthcheck(.unhealthy)
        )

        XCTAssertEqual(notification?.source, .docker)
        XCTAssertEqual(notification?.dedupeKey, "docker.gitlab-digest.healthcheck.unhealthy")
        XCTAssertEqual(notification?.symbol, "heart.slash")
        XCTAssertEqual(notification?.accent.style, .destructive)
        XCTAssertEqual(notification?.message, localized("%@ is unhealthy", spec.name))
    }

    func testDockerNotificationsSuppressTransitionsWithoutLocalizedCopy() {
        XCTAssertNil(NotchNotification.docker(name: spec.name, change: .runtime(.created)))
        XCTAssertNil(NotchNotification.docker(name: spec.name, change: .healthcheck(.starting)))
        XCTAssertNil(NotchNotification.docker(name: spec.name, change: .healthcheck(.none)))
        XCTAssertNil(NotchNotification.docker(name: spec.name, change: .httpHealth(.degraded)))
        XCTAssertNil(NotchNotification.docker(name: spec.name, change: .httpHealth(.none)))
    }

    func testSummaryWithZeroSnapshotsReturnsZeroSlashZero() {
        XCTAssertEqual(DockerStore.summary(snapshots: []), "0/0")
    }

    func testSummaryCountsOnlyRunningSnapshots() {
        let snapshots = [
            makeSnapshot(runtime: .running),
            makeSnapshot(runtime: .running),
            makeSnapshot(runtime: .exited),
        ]

        XCTAssertEqual(DockerStore.summary(snapshots: snapshots), "2/3")
    }

    func testSummaryDoesNotCountRestartingAsRunning() {
        let snapshots = [
            makeSnapshot(runtime: .running),
            makeSnapshot(runtime: .restarting),
        ]

        XCTAssertEqual(DockerStore.summary(snapshots: snapshots), "1/2")
    }

    func testStartAvailabilityOnStoppedStates() {
        for runtime in [DockerRuntimeState.exited, .created, .paused, .dead] {
            XCTAssertTrue(
                DockerAction.start.availability(for: runtime),
                "start should be available for \(runtime)"
            )
        }
    }

    func testRestartAndKillAvailabilityOnRunningStates() {
        for runtime in [DockerRuntimeState.running, .restarting] {
            XCTAssertTrue(
                DockerAction.restart.availability(for: runtime),
                "restart should be available for \(runtime)"
            )
            XCTAssertTrue(
                DockerAction.kill.availability(for: runtime),
                "kill should be available for \(runtime)"
            )
        }
    }

    func testNoActionsAvailableWhenContainerMissing() {
        for action in [DockerAction.start, .restart, .kill] {
            XCTAssertFalse(
                action.availability(for: .missing),
                "\(action) should not be available for missing"
            )
        }
    }

    func testPublishedPortsFromInspectDict() {
        let inspect: [String: Any] = [
            "NetworkSettings": [
                "Ports": [
                    "8787/tcp": [
                        ["HostIp": "127.0.0.1", "HostPort": "8787"],
                    ],
                ],
            ],
        ]

        let ports = DockerInspectParser.publishedPorts(from: inspect)

        XCTAssertEqual(ports.count, 1)
        XCTAssertEqual(ports[0].hostIP, "127.0.0.1")
        XCTAssertEqual(ports[0].hostPort, "8787")
        XCTAssertEqual(ports[0].proto, "tcp")
    }

    func testPublishedPortsAreSortedDeterministically() {
        let inspect: [String: Any] = [
            "NetworkSettings": [
                "Ports": [
                    "9000/udp": [
                        ["HostIp": "127.0.0.1", "HostPort": "9000"],
                    ],
                    "80/tcp": [
                        ["HostIp": "0.0.0.0", "HostPort": "8080"],
                        ["HostIp": "127.0.0.1", "HostPort": "8080"],
                    ],
                ],
            ],
        ]

        let ports = DockerInspectParser.publishedPorts(from: inspect)

        XCTAssertEqual(
            ports.map(\.id),
            ["0.0.0.0:8080/tcp", "127.0.0.1:8080/tcp", "127.0.0.1:9000/udp"]
        )
    }

    func testDockerCLIPlacesOptionTerminatorBeforeContainerName() {
        XCTAssertEqual(
            DockerCLI.arguments(for: .inspect, name: "-dangerous"),
            ["inspect", "--size", "--type", "container", "--", "-dangerous"]
        )
        XCTAssertEqual(
            DockerCLI.arguments(for: .action(.start), name: "-dangerous"),
            ["start", "--", "-dangerous"]
        )
        XCTAssertEqual(
            DockerCLI.arguments(for: .action(.restart), name: "-dangerous"),
            ["restart", "--", "-dangerous"]
        )
        XCTAssertEqual(
            DockerCLI.arguments(for: .action(.kill), name: "-dangerous"),
            ["kill", "--", "-dangerous"]
        )
    }

    private func makeSnapshot(
        runtime: DockerRuntimeState = .running,
        healthcheck: DockerHealthcheck = .none,
        httpHealth: DockerHTTPHealth = .none,
        ports: [DockerPublishedPort] = [],
        sizeBytes: Int64? = nil
    ) -> DockerServiceSnapshot {
        DockerServiceSnapshot(
            spec: spec,
            runtime: runtime,
            healthcheck: healthcheck,
            httpHealth: httpHealth,
            ports: ports,
            sizeBytes: sizeBytes,
            error: nil
        )
    }
}
