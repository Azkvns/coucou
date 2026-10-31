import AppKit
import Combine
import SwiftUI

enum ToolboxTab: String, CaseIterable, Identifiable {
    case translate, pipelines, services, terminal, ports, calendar, clipboard, notifications
    // Retained only for the imported privacy model; these panes are not exposed.
    case snippets, notes
    var id: String { rawValue }
    static var visible: [Self] { allCases.filter { $0 != .snippets && $0 != .notes } }
    var title: String {
        switch self {
        case .translate: return localized("Translate")
        case .services: return "Docker"
        case .pipelines: return localized("Pipelines")
        case .terminal: return localized("Terminal")
        case .ports: return localized("Ports")
        case .calendar: return localized("Calendar")
        case .clipboard: return localized("Clipboard")
        case .notifications: return localized("Notifications")
        case .snippets, .notes: return rawValue
        }
    }
}

@MainActor final class TabVisibility: ObservableObject {
    func isEnabled(_ tab: ToolboxTab) -> Bool { ToolboxTab.visible.contains(tab) }
}

/// A separate tools workspace: agent sessions keep using Coucou's island.
@MainActor public final class ToolboxController: NSObject, NSWindowDelegate {
    public static let shared = ToolboxController()
    public var onNotification: ((String, String) -> Void)?
    private var window: NSWindow?
    private var model: ToolboxModel?

    public func start() {
        guard model == nil else { return }
        let model = ToolboxModel()
        self.model = model
        model.onNotification = { [weak self] message, symbol in self?.onNotification?(message, symbol) }
        model.start()
    }

    public func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        start()
        guard let model else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Coucou — Tools"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 740, height: 480)
        window.contentView = NSHostingView(rootView: ToolboxView(model: model).preferredColorScheme(.dark))
        window.delegate = self
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowDidBecomeKey(_ notification: Notification) { model?.setVisible(true) }
    public func windowDidResignKey(_ notification: Notification) { model?.setVisible(false) }
    public func windowWillClose(_ notification: Notification) { model?.setVisible(false) }
    public func shutdown() { model?.shutdown() }
}

@MainActor final class ToolboxModel: ObservableObject {
    @Published var tab: ToolboxTab = .translate { didSet { syncPolling() } }
    @Published var visible = false
    @Published var clipboardEnabled = false {
        didSet { clipboardEnabled ? clipboard.start() : clipboard.stop() }
    }
    @Published var history: [NotchNotification] = []
    @Published var importStatus = ""
    @Published var storageError: String?
    let translator = Translator()
    let clipboard = ClipboardStore()
    let calendar = CalendarStore()
    let privacy = PrivacyMode()
    let ports = PortStore()
    lazy var pipelines = PipelineStore()
    lazy var terminal = TerminalStore()
    private let catalog = DockerCatalog()
    lazy var docker = DockerStore(catalog: catalog)
    private let center = TabNotificationCenter()
    private let visibility = TabVisibility()
    private var pipelineObserver: PipelineNotificationObserver?
    private var calendarObserver: CalendarNotificationObserver?
    private var dockerObserver: DockerNotificationObserver?
    var onNotification: ((String, String) -> Void)?

    func importCyclop() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select Cyclop's Application Support folder. Existing Coucou records are kept; imported commands do not run."
        panel.directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cyclop")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try CyclopImport(directory: url)
            pipelines.importPipelines(imported.pipelines)
            terminal.importTabs(imported.terminals)
            // Docker's catalog lives in preferences, not in the selected folder.
            let old = UserDefaults.standard.persistentDomain(forName: "com.cyclop.app")
            if let data = old?[DockerCatalog.storageKey] as? Data,
               let services = try? JSONDecoder().decode([DockerServiceSpec].self, from: data) {
                for service in services { _ = catalog.add(name: service.name, healthURL: service.healthURL) }
            }
            importStatus = "Import complete. Existing IDs and Docker names were kept."
        } catch { importStatus = "Import failed: \(error.localizedDescription)" }
    }

    func start() {
        do { try CyclopImport.validateDestination(Support.folder) }
        catch {
            storageError = "Saved Tools settings cannot be read. The files were kept: \(error.localizedDescription)"
            return
        }
        center.isFullyCollapsed = { true }
        center.onPush = { [weak self] item in
            guard let self else { return }
            if let key = item.dedupeKey { history.removeAll { $0.dedupeKey == key } }
            history.insert(item, at: 0)
            history = Array(history.prefix(100))
            if !visible { onNotification?(item.message, item.symbol) }
        }
        pipelineObserver = PipelineNotificationObserver(center: center, visibility: visibility)
        pipelineObserver?.install(store: pipelines)
        calendarObserver = CalendarNotificationObserver(center: center, visibility: visibility, privacy: privacy)
        calendarObserver?.install(store: calendar)
        dockerObserver = DockerNotificationObserver(center: center, visibility: visibility,
                                                    isPanelActive: { [weak self] in self?.visible == true && self?.tab == .services })
        dockerObserver?.install(store: docker)
        calendar.start() // Reads existing authorization; permission is requested by the Calendar button.
    }

    func setVisible(_ active: Bool) {
        visible = active
        if !active { privacy.coverEverything() }
        syncPolling()
    }

    private func syncPolling() {
        ports.setTabActive(tab == .ports)
        ports.setPanelActive(visible)
        docker.setTabActive(tab == .services)
        docker.setPanelActive(visible)
        dockerObserver?.panelActiveChanged()
        if visible && tab == .calendar { calendar.refreshAccess() }
    }

    func shutdown() {
        guard storageError == nil else { return }
        clipboard.stop()
        calendar.stop()
        ports.stop()
        docker.stop()
        pipelines.shutdown()
        terminal.flush()
        terminal.terminateAll()
        pipelineObserver?.teardown()
        calendarObserver?.teardown()
        dockerObserver?.teardown()
    }
}

private struct ToolboxView: View {
    @ObservedObject var model: ToolboxModel
    var body: some View {
        VStack(spacing: 12) {
            Picker("Tools", selection: $model.tab) {
                ForEach(ToolboxTab.visible) { Text($0.title).tag($0) }
            }.pickerStyle(.segmented)
            if let error = model.storageError {
                Text(error).textSelection(.enabled).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text(model.importStatus).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Import Cyclop…") { model.importCyclop() }
                    .disabled(model.storageError != nil)
            }
        }
        .padding(18)
        .background(Color.black.opacity(0.94))
    }

    @ViewBuilder private var content: some View {
        switch model.tab {
        case .translate: TranslatePane(translator: model.translator, wantsKeyboard: $model.visible)
        case .pipelines: PipelinesPane(pipelines: model.pipelines, wantsKeyboard: $model.visible)
        case .services: DockerPane(store: model.docker)
        case .terminal: TerminalPane(terminal: model.terminal, wantsKeyboard: $model.visible)
        case .ports: PortsPane(ports: model.ports)
        case .calendar: CalendarPane(calendar: model.calendar, privacy: model.privacy)
        case .clipboard:
            VStack {
                Toggle("Record clipboard history", isOn: $model.clipboardEnabled)
                ClipboardPane(clipboard: model.clipboard, privacy: model.privacy)
            }
        case .notifications:
            List(model.history) { item in Label(item.message, systemImage: item.symbol).textSelection(.enabled) }
        case .snippets, .notes: EmptyView()
        }
    }
}
