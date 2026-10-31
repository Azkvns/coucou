import Foundation
import XCTest
@testable import CoucouToolbox

@MainActor
final class DockerCatalogTests: XCTestCase {
    private let suiteName = "com.coucou.toolbox.tests.docker-catalog"

    override func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: suiteName)!
    }

    func testEmptyDefault() {
        let catalog = DockerCatalog(defaults: makeDefaults())
        XCTAssertTrue(catalog.services.isEmpty)
    }

    func testAdd() {
        let catalog = DockerCatalog(defaults: makeDefaults())
        let result = catalog.add(name: "my-container", healthURL: "http://localhost/health")

        guard case .success(let spec) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(spec.name, "my-container")
        XCTAssertEqual(spec.healthURL, "http://localhost/health")
        XCTAssertEqual(catalog.services.count, 1)
        XCTAssertEqual(catalog.services[0].id, spec.id)
    }

    func testAddTrimsName() {
        let catalog = DockerCatalog(defaults: makeDefaults())
        let result = catalog.add(name: "  my-container  ", healthURL: nil)

        guard case .success(let spec) = result else {
            XCTFail("Expected success")
            return
        }

        XCTAssertEqual(spec.name, "my-container")
    }

    func testEmptyHealthURLBecomesNil() {
        let catalog = DockerCatalog(defaults: makeDefaults())

        let empty = catalog.add(name: "container", healthURL: "")
        guard case .success(let spec) = empty else {
            XCTFail("Expected success")
            return
        }
        XCTAssertNil(spec.healthURL)

        let whitespace = catalog.add(name: "container2", healthURL: "   ")
        guard case .success(let spec2) = whitespace else {
            XCTFail("Expected success")
            return
        }
        XCTAssertNil(spec2.healthURL)
    }

    func testDuplicateName() {
        let catalog = DockerCatalog(defaults: makeDefaults())
        _ = catalog.add(name: "duplicate", healthURL: nil)

        let result = catalog.add(name: "duplicate", healthURL: nil)

        guard case .failure(.duplicateName) = result else {
            XCTFail("Expected duplicateName error")
            return
        }
        XCTAssertEqual(catalog.services.count, 1)
    }

    func testDuplicateNameIsCaseSensitive() {
        let catalog = DockerCatalog(defaults: makeDefaults())
        _ = catalog.add(name: "MyContainer", healthURL: nil)

        let result = catalog.add(name: "mycontainer", healthURL: nil)

        guard case .success = result else {
            XCTFail("Expected success for case-different name")
            return
        }
        XCTAssertEqual(catalog.services.count, 2)
    }

    func testEmptyName() {
        let catalog = DockerCatalog(defaults: makeDefaults())
        let result = catalog.add(name: "   ", healthURL: nil)

        guard case .failure(.emptyName) = result else {
            XCTFail("Expected emptyName error")
            return
        }
        XCTAssertTrue(catalog.services.isEmpty)
    }

    func testRejectsInvalidContainerNames() {
        let catalog = DockerCatalog(defaults: makeDefaults())

        for name in ["-dangerous", ".hidden", "_private", "has space", "name/child", "name$"] {
            guard case .failure(.invalidName) = catalog.add(name: name, healthURL: nil) else {
                XCTFail("Expected invalidName for \(name)")
                continue
            }
        }

        XCTAssertTrue(catalog.services.isEmpty)
    }

    func testAcceptsDockerContainerNameCharacters() {
        let catalog = DockerCatalog(defaults: makeDefaults())

        let result = catalog.add(name: "A1_name.with-dashes", healthURL: nil)

        guard case .success(let spec) = result else {
            XCTFail("Expected valid container name")
            return
        }
        XCTAssertEqual(spec.name, "A1_name.with-dashes")
    }

    func testInvalidHealthURL() {
        let catalog = DockerCatalog(defaults: makeDefaults())
        let result = catalog.add(name: "container", healthURL: "ftp://example.com")

        guard case .failure(.invalidHealthURL) = result else {
            XCTFail("Expected invalidHealthURL error")
            return
        }
        XCTAssertTrue(catalog.services.isEmpty)
    }

    func testPersistAndReload() {
        let defaults = makeDefaults()
        var addedSpec: DockerServiceSpec!

        do {
            let catalog = DockerCatalog(defaults: defaults)
            let result = catalog.add(name: "persisted", healthURL: "https://example.com/health")
            guard case .success(let spec) = result else {
                XCTFail("Expected success")
                return
            }
            addedSpec = spec
        }

        let reloaded = DockerCatalog(defaults: defaults)
        XCTAssertEqual(reloaded.services.count, 1)
        XCTAssertEqual(reloaded.services[0], addedSpec)
    }

    func testInsertionOrder() {
        let catalog = DockerCatalog(defaults: makeDefaults())
        _ = catalog.add(name: "first", healthURL: nil)
        _ = catalog.add(name: "second", healthURL: nil)
        _ = catalog.add(name: "third", healthURL: nil)

        XCTAssertEqual(catalog.services.map(\.name), ["first", "second", "third"])
    }

    func testRemove() {
        let defaults = makeDefaults()
        let catalog = DockerCatalog(defaults: defaults)
        let result = catalog.add(name: "to-remove", healthURL: nil)

        guard case .success(let spec) = result else {
            XCTFail("Expected success")
            return
        }

        catalog.remove(id: spec.id)
        XCTAssertTrue(catalog.services.isEmpty)

        let reloaded = DockerCatalog(defaults: defaults)
        XCTAssertTrue(reloaded.services.isEmpty)
    }

    func testRefreshFailureKeepsLastSuccessfulSnapshots() async {
        let catalog = DockerCatalog(defaults: makeDefaults())
        guard case .success(let spec) = catalog.add(name: "stable", healthURL: nil) else {
            XCTFail("Expected service to be added")
            return
        }

        let snapshot = DockerServiceSnapshot(
            spec: spec,
            runtime: .running,
            healthcheck: .healthy,
            httpHealth: .none,
            ports: [],
            sizeBytes: 42,
            error: nil
        )
        let cli = DockerSequenceExecutor(results: [
            .success([snapshot]),
            .failure(.commandFailed("inspect failed")),
        ])
        let store = DockerStore(catalog: catalog, cli: cli)

        store.setTabActive(true)
        store.setPanelActive(true)
        await waitUntil { store.snapshots == [snapshot] }

        store.refreshNow()
        await waitUntil { store.lastError == "inspect failed" }

        XCTAssertEqual(store.snapshots, [snapshot])
        store.stop()
    }

    private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async {
        for _ in 0..<100 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for condition")
    }
}

private actor DockerSequenceExecutor: DockerExecuting {
    private var results: [Result<[DockerServiceSnapshot], DockerCLIError>]

    init(results: [Result<[DockerServiceSnapshot], DockerCLIError>]) {
        self.results = results
    }

    func snapshots(for specs: [DockerServiceSpec]) async -> Result<[DockerServiceSnapshot], DockerCLIError> {
        guard !results.isEmpty else {
            return .failure(.commandFailed("no queued result"))
        }
        return results.removeFirst()
    }

    func perform(_ action: DockerAction, name: String) async -> Result<Void, DockerCLIError> {
        .success(())
    }
}
