import Combine
import Foundation

extension DockerAction {
    func availability(for runtime: DockerRuntimeState) -> Bool {
        switch (self, runtime) {
        case (.start, .exited),
             (.start, .created),
             (.start, .paused),
             (.start, .dead),
             (.restart, .running),
             (.restart, .restarting),
             (.kill, .running),
             (.kill, .restarting):
            return true
        default:
            return false
        }
    }
}

/// Docker service snapshots and actions for the visible Docker panel.
///
/// Polling runs only while both the Docker tab and its panel are active.
@MainActor
final class DockerStore: ObservableObject {
    @Published private(set) var snapshots: [DockerServiceSnapshot] = []
    @Published private(set) var lastError: String?
    @Published private(set) var pendingActions: [UUID: DockerAction] = [:]
    @Published var lastActionError: String?

    private let catalog: DockerCatalog
    private let cli: any DockerExecuting
    private var timer: Timer?
    private var tabActive = false
    private var panelActive = false
    private var refreshGeneration: UInt64 = 0
    private var cancellables = Set<AnyCancellable>()

    init(catalog: DockerCatalog, cli: any DockerExecuting = DockerCLI()) {
        self.catalog = catalog
        self.cli = cli

        catalog.$services
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshNow()
                }
            }
            .store(in: &cancellables)
    }

    func setTabActive(_ active: Bool) {
        tabActive = active
        if !active {
            refreshGeneration &+= 1
            lastError = nil
            lastActionError = nil
        }
        syncPolling()
    }

    func setPanelActive(_ active: Bool) {
        panelActive = active
        if !active {
            refreshGeneration &+= 1
        }
        syncPolling()
    }

    func stop() {
        tabActive = false
        panelActive = false
        refreshGeneration &+= 1
        stopTimer()
        snapshots = []
        lastError = nil
        lastActionError = nil
    }

    func refreshNow() {
        guard tabActive, panelActive else { return }

        refreshGeneration &+= 1
        let generation = refreshGeneration
        let specs = catalog.services

        Task {
            let result = await cli.snapshots(for: specs)
            guard generation == refreshGeneration else { return }

            switch result {
            case .success(let snapshots):
                self.snapshots = snapshots
                lastError = nil
            case .failure(let error):
                lastError = Self.message(for: error)
            }
        }
    }

    func probeSnapshots() async -> Result<[DockerServiceSnapshot], DockerCLIError> {
        await cli.snapshots(for: catalog.services)
    }

    func addService(name: String, healthURL: String?) {
        switch catalog.add(name: name, healthURL: healthURL) {
        case .success:
            lastActionError = nil
        case .failure(let error):
            lastActionError = Self.message(for: error)
        }
    }

    func removeService(id: UUID) {
        pendingActions[id] = nil
        catalog.remove(id: id)
        lastActionError = nil
    }

    func perform(_ action: DockerAction, id: UUID) async {
        guard !isBusy(id) else { return }
        guard let snapshot = snapshots.first(where: { $0.spec.id == id }) else {
            lastActionError = "Container not found"
            return
        }
        guard snapshot.runtime != .missing else {
            lastActionError = "Container not found"
            return
        }
        guard action.availability(for: snapshot.runtime) else {
            switch action {
            case .start:
                lastActionError = "Container is not stopped"
            case .restart, .kill:
                lastActionError = "Container is not running"
            }
            return
        }

        pendingActions[id] = action
        lastActionError = nil
        let result = await cli.perform(action, name: snapshot.spec.name)
        pendingActions[id] = nil

        switch result {
        case .success:
            lastActionError = nil
        case .failure(let error):
            lastActionError = Self.message(for: error)
        }
        refreshNow()
    }

    func isBusy(_ id: UUID) -> Bool {
        pendingActions[id] != nil
    }

    var headerSummary: String {
        Self.summary(snapshots: snapshots)
    }

    nonisolated static func summary(snapshots: [DockerServiceSnapshot]) -> String {
        let runningCount = snapshots.lazy.filter { $0.runtime == .running }.count
        return "\(runningCount)/\(snapshots.count)"
    }

    private func syncPolling() {
        let shouldPoll = tabActive && panelActive
        guard shouldPoll else {
            stopTimer()
            return
        }

        refreshNow()
        startTimer()
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshNow()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private static func message(for error: DockerCLIError) -> String {
        switch error {
        case .dockerNotFound:
            return "Docker CLI not found"
        case .dockerNotRunning:
            return "Docker is not running"
        case .commandFailed(let message):
            return message
        }
    }

    private static func message(for error: DockerCatalogError) -> String {
        switch error {
        case .emptyName:
            return "Container name is required"
        case .invalidName:
            return "Invalid container name"
        case .duplicateName:
            return "Container already exists"
        case .invalidHealthURL:
            return "Invalid health URL"
        }
    }
}
