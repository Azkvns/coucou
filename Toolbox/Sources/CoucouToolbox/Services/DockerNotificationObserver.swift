import Combine
import Foundation

/// Observes Docker service state and posts notch notifications while collapsed.
@MainActor
final class DockerNotificationObserver {
    private weak var store: DockerStore?
    private let center: TabNotificationCenter
    private let visibility: TabVisibility
    private let isPanelActive: () -> Bool

    private var previousSnapshots: [UUID: DockerServiceSnapshot] = [:]
    private var suppressedActionIDs: Set<UUID> = []
    private var backgroundTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(
        center: TabNotificationCenter,
        visibility: TabVisibility,
        isPanelActive: @escaping () -> Bool
    ) {
        self.center = center
        self.visibility = visibility
        self.isPanelActive = isPanelActive
    }

    func install(store: DockerStore) {
        self.store = store

        store.$snapshots
            .sink { [weak self] snapshots in
                guard let self, isPanelActive() else { return }
                handle(snapshots)
            }
            .store(in: &cancellables)

        store.$pendingActions
            .sink { [weak self] actions in
                self?.suppressedActionIDs.formUnion(actions.keys)
            }
            .store(in: &cancellables)

        visibility.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    await Task.yield()
                    self?.syncBackgroundMonitoring()
                }
            }
            .store(in: &cancellables)

        syncBackgroundMonitoring()
    }

    func teardown() {
        cancellables.removeAll()
        stopBackgroundTimer()
        previousSnapshots.removeAll()
        suppressedActionIDs.removeAll()
        store = nil
    }

    func panelActiveChanged() {
        syncBackgroundMonitoring()
    }

    private func syncBackgroundMonitoring() {
        guard visibility.isEnabled(.services) else {
            stopBackgroundTimer()
            previousSnapshots.removeAll()
            suppressedActionIDs.removeAll()
            return
        }

        if isPanelActive() {
            stopBackgroundTimer()
            if let store {
                handle(store.snapshots)
            }
        } else {
            startBackgroundTimer()
        }
    }

    private func startBackgroundTimer() {
        guard backgroundTimer == nil, visibility.isEnabled(.services) else { return }

        probeBackground()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.probeBackground() }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        backgroundTimer = timer
    }

    private func stopBackgroundTimer() {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
    }

    private func probeBackground() {
        guard visibility.isEnabled(.services), !isPanelActive(), let store else { return }

        Task {
            guard case .success(let snapshots) = await store.probeSnapshots() else { return }
            handle(snapshots)
        }
    }

    private func handle(_ snapshots: [DockerServiceSnapshot]) {
        guard visibility.isEnabled(.services), let store else { return }

        let currentIDs = Set(snapshots.map(\.spec.id))
        previousSnapshots = previousSnapshots.filter { currentIDs.contains($0.key) }

        for snapshot in snapshots {
            let id = snapshot.spec.id
            guard let previous = previousSnapshots[id] else {
                previousSnapshots[id] = snapshot
                continue
            }

            if store.pendingActions[id] != nil || suppressedActionIDs.contains(id) {
                previousSnapshots[id] = snapshot
                if store.pendingActions[id] == nil {
                    suppressedActionIDs.remove(id)
                }
                continue
            }

            for change in DockerSnapshotDiff.changes(from: previous, to: snapshot) {
                if let notification = NotchNotification.docker(name: snapshot.spec.name, change: change) {
                    center.post(notification)
                }
            }
            previousSnapshots[id] = snapshot
        }
    }
}
