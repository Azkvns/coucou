import Combine
import Foundation

/// Embedded terminal tabs: several shells, persisted between launches.
@MainActor
final class TerminalStore: ObservableObject {
    @Published private(set) var tabs: [TerminalTab] = []
    @Published var selectedTabID: UUID?

    var selected: TerminalTab? {
        guard let selectedTabID else { return tabs.first }
        return tabs.first(where: { $0.id == selectedTabID }) ?? tabs.first
    }

    private var sessions: [UUID: TerminalSessionController] = [:]
    private weak var attachedContainer: TerminalContainerView?
    private var attachedTabID: UUID?
    private let saves = DebouncedWrite()

    private static let file = Support.file("terminals.json")

    init() {
        load()
        if tabs.isEmpty {
            let tab = TerminalTab.makeDefault()
            tabs = [tab]
            selectedTabID = tab.id
            persist()
        } else if selectedTabID == nil {
            selectedTabID = tabs.first?.id
        }
    }

    // MARK: - Tab CRUD

    func importTabs(_ imported: [TerminalTab]) {
        var known = Set(tabs.map(\.id))
        tabs.append(contentsOf: imported.filter { known.insert($0.id).inserted })
        persist()
    }

    func ensureDefaultTab() {
        guard tabs.isEmpty else { return }
        let tab = TerminalTab.makeDefault()
        tabs = [tab]
        selectedTabID = tab.id
        scheduleSave()
    }

    func addTab() {
        let cwd = selected?.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        let tab = TerminalTab.makeDefault(cwd: cwd)
        tabs.append(tab)
        selectedTabID = tab.id
        scheduleSave()
    }

    func closeSelectedTab() {
        guard tabs.count > 1, let id = selected?.id else { return }
        closeTab(id)
    }

    func closeTab(_ id: UUID) {
        guard tabs.count > 1 else { return }
        if attachedTabID == id { detachView() }
        sessions[id]?.terminate()
        sessions.removeValue(forKey: id)
        tabs.removeAll { $0.id == id }
        if selectedTabID == id {
            selectedTabID = tabs.first?.id
        }
        scheduleSave()
    }

    func selectTab(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        persistCWDs()
        selectedTabID = id
        scheduleSave()
        reattachIfNeeded()
    }

    var canCloseSelectedTab: Bool { tabs.count > 1 }

    // MARK: - View attachment

    func attachView(to container: TerminalContainerView, tabID: UUID) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }
        if attachedTabID != tabID {
            detachView()
        }
        attachedContainer = container
        attachedTabID = tabID
        let session = session(for: tabID)
        session.attach(to: container)
    }

    func detachView() {
        if let id = attachedTabID {
            persistCWD(for: id)
            sessions[id]?.detach()
        }
        attachedContainer = nil
        attachedTabID = nil
    }

    func detachViewIfAttached(to container: TerminalContainerView) {
        guard attachedContainer === container else { return }
        detachView()
    }

    var selectedSessionHasExited: Bool {
        guard let id = selectedTabID else { return false }
        return sessions[id]?.hasExited ?? false
    }

    func reattachIfNeeded() {
        guard let container = attachedContainer, let id = selectedTabID else { return }
        attachView(to: container, tabID: id)
    }

    func layoutChanged(for container: TerminalContainerView) {
        guard attachedContainer === container, let id = attachedTabID else { return }
        session(for: id).spawnIfNeeded(in: container.bounds)
    }

    func restartSelectedTab() {
        guard let id = selected?.id else { return }
        sessions[id]?.terminate()
        sessions.removeValue(forKey: id)
        reattachIfNeeded()
    }

    // MARK: - Lifecycle

    func persistCWDs() {
        for tab in tabs {
            persistCWD(for: tab.id)
        }
    }

    func terminateAll() {
        detachView()
        for session in sessions.values {
            session.terminate()
        }
        sessions.removeAll()
    }

    func flush() {
        persistCWDs()
        saves.flush()
    }

    // MARK: - Sessions

    private func session(for id: UUID) -> TerminalSessionController {
        if let existing = sessions[id] {
            if let tab = tabs.first(where: { $0.id == id }) {
                existing.updateTab(tab)
            }
            return existing
        }
        guard let tab = tabs.first(where: { $0.id == id }) else {
            fatalError("TerminalStore: missing tab for session")
        }
        let controller = TerminalSessionController(tab: tab)
        controller.onTitleChange = { [weak self] title in
            self?.updateTitle(id, title: title)
        }
        controller.onDirectoryChange = { [weak self] directory in
            self?.updateCWD(id, cwd: directory)
        }
        controller.onExit = { [weak self] in
            self?.objectWillChange.send()
        }
        sessions[id] = controller
        return controller
    }

    private func updateTitle(_ id: UUID, title: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].title = title
        scheduleSave()
    }

    private func updateCWD(_ id: UUID, cwd: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].cwd = cwd
        scheduleSave()
    }

    private func persistCWD(for id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        if let cwd = sessions[id]?.captureCWD() {
            tabs[index].cwd = cwd
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.file),
              let document = try? JSONDecoder().decode(TerminalsDocument.self, from: data) else {
            if FileManager.default.fileExists(atPath: Self.file.path) {
                NSLog("Cyclop: terminals.json is not readable, starting fresh")
            }
            return
        }
        tabs = document.tabs
        selectedTabID = document.selectedTabID
    }

    private func scheduleSave() {
        saves.schedule { [weak self] in self?.persist() }
    }

    private func persist() {
        let document = TerminalsDocument(tabs: tabs, selectedTabID: selectedTabID)
        do {
            try JSONEncoder().encode(document).write(to: Self.file, options: .atomic)
        } catch {
            NSLog("Cyclop: cannot write terminals.json: \(error.localizedDescription)")
        }
    }
}
