import Combine
import Foundation

/// Bash command pipelines: cards arranged in order, run one after another.
///
/// Each pipeline runs at most one instance at a time, but different pipelines
/// may run in parallel. Execution continues in the background when the panel
/// closes — only disabling the tab or quitting stops the runners.
@MainActor
final class PipelineStore: ObservableObject {
    @Published private(set) var pipelines: [Pipeline] = []
    @Published var selectedPipelineID: UUID?

    var selected: Pipeline? {
        guard let selectedPipelineID else { return pipelines.first }
        return pipelines.first(where: { $0.id == selectedPipelineID }) ?? pipelines.first
    }

    var selectedRunner: PipelineRunner {
        let id = selected?.id ?? pipelines.first!.id
        return execution.runner(for: id)
    }

    var activeRunCount: Int { execution.activeCount }

    /// Called whenever a new runner is created for a pipeline ID.
    func wireRunnerCreated(_ handler: @escaping (PipelineRunner) -> Void) {
        execution.onRunnerCreated = handler
    }

    private let execution = PipelineExecutionManager()
    private let saves = DebouncedWrite()
    private var cancellables = Set<AnyCancellable>()

    private static let file = Support.file("pipelines.json")

    init() {
        execution.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        load()
        if pipelines.isEmpty {
            let pipeline = Pipeline(id: UUID(), name: nextName(), cards: [])
            pipelines = [pipeline]
            selectedPipelineID = pipeline.id
            persist()
        } else if selectedPipelineID == nil {
            selectedPipelineID = pipelines.first?.id
        }
    }

    // MARK: - Selection

    func importPipelines(_ imported: [Pipeline]) {
        var known = Set(pipelines.map(\.id))
        pipelines.append(contentsOf: imported.filter { known.insert($0.id).inserted })
        persist()
    }

    func selectPipeline(_ id: UUID) {
        guard pipelines.contains(where: { $0.id == id }) else { return }
        selectedPipelineID = id
        scheduleSave()
    }

    // MARK: - Pipeline CRUD

    func addPipeline() {
        let pipeline = Pipeline(id: UUID(), name: nextName(), cards: [])
        pipelines.append(pipeline)
        selectedPipelineID = pipeline.id
        scheduleSave()
    }

    func deleteSelectedPipeline() {
        guard pipelines.count > 1, let id = selected?.id else { return }
        guard !execution.isRunning(id) else { return }
        pipelines.removeAll { $0.id == id }
        selectedPipelineID = pipelines.first?.id
        scheduleSave()
    }

    var canDeleteSelectedPipeline: Bool {
        pipelines.count > 1 && !(selected.map { execution.isRunning($0.id) } ?? false)
    }

    // MARK: - Card CRUD

    func addCard() {
        guard var pipeline = selected, !execution.isRunning(pipeline.id) else { return }
        let card = PipelineCard(name: "", command: "")
        pipeline.cards.append(card)
        updatePipeline(pipeline)
    }

    func deleteCard(_ id: UUID) {
        guard var pipeline = selected, !execution.isRunning(pipeline.id) else { return }
        pipeline.cards.removeAll { $0.id == id }
        updatePipeline(pipeline)
    }

    func updateCard(_ id: UUID, name: String, command: String) {
        guard var pipeline = selected, !execution.isRunning(pipeline.id) else { return }
        guard let index = pipeline.cards.firstIndex(where: { $0.id == id }) else { return }
        pipeline.cards[index].name = name
        pipeline.cards[index].command = command
        updatePipeline(pipeline)
    }

    func moveCard(_ id: UUID, to index: Int) {
        guard var pipeline = selected, !execution.isRunning(pipeline.id) else { return }
        guard let current = pipeline.cards.firstIndex(where: { $0.id == id }) else { return }
        let target = max(0, min(index, pipeline.cards.count - 1))
        guard target != current else { return }
        pipeline.cards.insert(pipeline.cards.remove(at: current), at: target)
        updatePipeline(pipeline)
    }

    // MARK: - Execution

    func runSelectedPipeline() {
        guard let pipeline = selected, !execution.isRunning(pipeline.id) else { return }
        let cards = pipeline.cards.filter {
            !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !cards.isEmpty else { return }
        execution.runner(for: pipeline.id).runAll(cards: pipeline.cards)
    }

    func runCard(_ id: UUID) {
        guard let pipeline = selected, !execution.isRunning(pipeline.id) else { return }
        execution.runner(for: pipeline.id).runSingle(cardID: id, cards: pipeline.cards)
    }

    func stopSelected() {
        guard let pipeline = selected else { return }
        execution.runner(for: pipeline.id).stop()
    }

    func continueAfterError() {
        guard let pipeline = selected else { return }
        execution.runner(for: pipeline.id).continueAfterError()
    }

    func abortAfterError() {
        guard let pipeline = selected else { return }
        execution.runner(for: pipeline.id).abortAfterError()
    }

    func runner(for pipelineID: UUID) -> PipelineRunner {
        execution.runner(for: pipelineID)
    }

    func stopAllRunners() async {
        await execution.stopAll()
    }

    func flush() {
        saves.flush()
    }

    func shutdown() {
        execution.stopAllImmediately()
        flush()
    }

    // MARK: - Persistence

    private func updatePipeline(_ pipeline: Pipeline) {
        guard let index = pipelines.firstIndex(where: { $0.id == pipeline.id }) else { return }
        pipelines[index] = pipeline
        scheduleSave()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.file),
              let document = try? JSONDecoder().decode(PipelinesDocument.self, from: data) else {
            if FileManager.default.fileExists(atPath: Self.file.path) {
                NSLog("Cyclop: pipelines.json is not readable, starting fresh")
            }
            return
        }
        pipelines = document.pipelines
        selectedPipelineID = document.selectedPipelineID
    }

    private func scheduleSave() {
        saves.schedule { [weak self] in self?.persist() }
    }

    private func persist() {
        let document = PipelinesDocument(
            pipelines: pipelines,
            selectedPipelineID: selectedPipelineID
        )
        do {
            try JSONEncoder().encode(document).write(to: Self.file, options: .atomic)
        } catch {
            NSLog("Cyclop: cannot write pipelines.json: \(error.localizedDescription)")
        }
    }

    private func nextName() -> String {
        var candidate = 1
        let names = Set(pipelines.map(\.name))
        while names.contains(localized("Pipeline %d", candidate)) {
            candidate += 1
        }
        return localized("Pipeline %d", candidate)
    }
}
