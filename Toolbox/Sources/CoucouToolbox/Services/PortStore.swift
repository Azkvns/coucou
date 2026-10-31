import Darwin
import Foundation

/// Open network ports and the processes that hold them.
///
/// Polling runs only while the ports tab is showing on an open panel — the
/// same discipline as the calendar countdown: no subprocess every five seconds
/// for eyes that are not looking.
@MainActor
final class PortStore: ObservableObject {
    @Published private(set) var bindings: [PortBinding] = []
    @Published var ownerFilter: PortOwnerFilter = .mine
    @Published var stateFilter: PortStateFilter = .listen
    @Published var sortOrder: PortSortOrder = .newestFirst
    @Published var protoFilter: PortProtoFilter = .all
    @Published private(set) var isScanning = false
    @Published private(set) var lastError: String?
    @Published var killError: String?

    var filtered: [PortBinding] {
        displayedBindings
    }

    var displayedBindings: [PortBinding] {
        let mine = getuid()
        let filtered = bindings.filter { binding in
            switch ownerFilter {
            case .mine where binding.uid != mine:
                return false
            case .mine, .all:
                break
            }
            switch stateFilter {
            case .listen where !binding.isListening && binding.state != "UDP":
                return false
            case .established where !binding.isEstablished:
                return false
            case .listen, .established, .all:
                break
            }
            switch protoFilter {
            case .tcp where binding.proto != "TCP":
                return false
            case .udp where binding.proto != "UDP":
                return false
            case .all, .tcp, .udp:
                break
            }
            return true
        }
        return sort(filtered)
    }

    private let scanner: any PortScanner
    private var timer: Timer?
    private var tabActive = false
    private var panelActive = false
    private var scanGeneration: UInt64 = 0
    private var firstSeenByID: [String: Date] = [:]
    private var lastScanStartedAt: Date?

    init(scanner: any PortScanner = LsofPortScanner()) {
        self.scanner = scanner
    }

    func isNew(_ binding: PortBinding) -> Bool {
        guard let lastScanStartedAt else { return false }
        return binding.firstSeenAt >= lastScanStartedAt
    }

    func setTabActive(_ active: Bool) {
        tabActive = active
        if !active {
            killError = nil
            lastError = nil
            scanGeneration &+= 1
        }
        syncPolling()
    }

    func setPanelActive(_ active: Bool) {
        panelActive = active
        if !active {
            scanGeneration &+= 1
        }
        syncPolling()
    }

    func stop() {
        setTabActive(false)
        setPanelActive(false)
        bindings = []
        firstSeenByID = [:]
        lastScanStartedAt = nil
    }

    func refreshNow() {
        guard tabActive, panelActive else { return }

        scanGeneration &+= 1
        let generation = scanGeneration
        let scanStartedAt = Date()
        lastScanStartedAt = scanStartedAt
        isScanning = true

        Task {
            do {
                let result = try await scanner.scan()
                guard generation == scanGeneration else { return }
                bindings = merge(result, at: scanStartedAt)
                lastError = nil
            } catch PortScanError.lsofMissing {
                guard generation == scanGeneration else { return }
                bindings = []
                firstSeenByID = [:]
                lastError = localized("Could not read ports")
            } catch {
                guard generation == scanGeneration else { return }
                bindings = []
                firstSeenByID = [:]
                lastError = localized("Could not read ports")
            }
            if generation == scanGeneration {
                isScanning = false
            }
        }
    }

    func terminate(_ binding: PortBinding) {
        killError = nil

        guard ProcessLookup.verify(binding) else {
            killError = localized("Process already exited")
            refreshNow()
            return
        }

        if Darwin.kill(binding.pid, SIGTERM) != 0 {
            killError = localized("Permission denied")
            return
        }

        Task {
            try? await Task.sleep(for: .seconds(2))
            if ProcessLookup.isAlive(binding.pid), ProcessLookup.verify(binding) {
                _ = Darwin.kill(binding.pid, SIGKILL)
            }
            refreshNow()
            if ProcessLookup.isAlive(binding.pid), ProcessLookup.verify(binding) {
                killError = localized("Could not stop process")
            }
        }
    }

    private func merge(_ scanned: [PortBinding], at now: Date) -> [PortBinding] {
        var seenIDs = Set<String>()
        var merged: [PortBinding] = []

        for binding in scanned {
            seenIDs.insert(binding.id)
            if firstSeenByID[binding.id] == nil {
                firstSeenByID[binding.id] = now
            }
            let firstSeenAt = firstSeenByID[binding.id] ?? now
            merged.append(
                binding.withTimestamps(
                    firstSeenAt: firstSeenAt,
                    processStartedAt: binding.processStartedAt
                )
            )
        }

        firstSeenByID = firstSeenByID.filter { seenIDs.contains($0.key) }
        return merged
    }

    private func sort(_ bindings: [PortBinding]) -> [PortBinding] {
        switch sortOrder {
        case .newestFirst:
            return bindings.sorted {
                if $0.firstSeenAt != $1.firstSeenAt { return $0.firstSeenAt > $1.firstSeenAt }
                return $0.port < $1.port
            }
        case .oldestFirst:
            return bindings.sorted {
                if $0.firstSeenAt != $1.firstSeenAt { return $0.firstSeenAt < $1.firstSeenAt }
                return $0.port < $1.port
            }
        case .portNumber:
            return bindings.sorted {
                if $0.port != $1.port { return $0.port < $1.port }
                return $0.processName.localizedCaseInsensitiveCompare($1.processName) == .orderedAscending
            }
        case .processName:
            return bindings.sorted {
                let nameOrder = $0.processName.localizedCaseInsensitiveCompare($1.processName)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
                return $0.port < $1.port
            }
        }
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
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

#if DEBUG
extension PortStore {
    func setBindingsForTesting(_ bindings: [PortBinding]) {
        self.bindings = bindings
    }

    func mergeForTesting(_ scanned: [PortBinding], at now: Date) -> [PortBinding] {
        merge(scanned, at: now)
    }

    func sortForTesting(_ bindings: [PortBinding]) -> [PortBinding] {
        sort(bindings)
    }
}
#endif
