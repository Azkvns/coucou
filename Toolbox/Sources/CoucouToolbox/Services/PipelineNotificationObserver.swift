import Combine
import Foundation

/// Observes pipeline runner phase transitions and posts banner notifications
/// while the panel is fully collapsed.
@MainActor
final class PipelineNotificationObserver {
    private weak var store: PipelineStore?
    private let center: TabNotificationCenter
    private let visibility: TabVisibility
    private var cancellables = Set<AnyCancellable>()
    private var previousPhases: [UUID: PipelinePhase] = [:]

    init(center: TabNotificationCenter, visibility: TabVisibility) {
        self.center = center
        self.visibility = visibility
    }

    func install(store: PipelineStore) {
        self.store = store
        store.wireRunnerCreated { [weak self] runner in
            self?.observe(runner)
        }
    }

    func teardown() {
        cancellables.removeAll()
        previousPhases.removeAll()
    }

    private func observe(_ runner: PipelineRunner) {
        runner.$phase
            .removeDuplicates()
            .sink { [weak self, weak runner] phase in
                guard let self, let runner else { return }
                let previous = previousPhases[runner.pipelineID] ?? .idle
                previousPhases[runner.pipelineID] = phase
                handleTransition(runner: runner, from: previous, to: phase)
            }
            .store(in: &cancellables)
    }

    private func handleTransition(runner: PipelineRunner, from previous: PipelinePhase, to phase: PipelinePhase) {
        guard visibility.isEnabled(.pipelines) else { return }
        let pipelineName = pipelineName(for: runner.pipelineID)

        switch (previous, phase) {
        case (.idle, .running(let index)):
            center.post(NotchNotification.pipeline(
                message: localized("Pipeline \"%@\" started", pipelineName)
            ))
            postStepStarted(pipelineID: runner.pipelineID, stepIndex: index)

        case (.running(let oldIndex), .running(let newIndex)) where newIndex > oldIndex:
            postStepCompleted(pipelineID: runner.pipelineID, stepIndex: oldIndex)
            postStepStarted(pipelineID: runner.pipelineID, stepIndex: newIndex)

        case (.running(let index), .awaitingDecision(_, let code)):
            center.post(NotchNotification.pipeline(
                message: localized("Step \"%@\" failed (exit %d)", cardName(for: runner.pipelineID, stepIndex: index), Int(code))
            ))

        case (.running, .idle):
            center.post(NotchNotification.pipeline(
                message: localized("Pipeline \"%@\" finished", pipelineName)
            ))

        case (_, .stopping):
            center.post(NotchNotification.pipeline(
                message: localized("Pipeline \"%@\" stopped", pipelineName)
            ))

        default:
            break
        }
    }

    private func postStepStarted(pipelineID: UUID, stepIndex: Int) {
        center.post(NotchNotification.pipeline(
            message: localized("Step \"%@\" started", cardName(for: pipelineID, stepIndex: stepIndex))
        ))
    }

    private func postStepCompleted(pipelineID: UUID, stepIndex: Int) {
        center.post(NotchNotification.pipeline(
            message: localized("Step \"%@\" completed", cardName(for: pipelineID, stepIndex: stepIndex))
        ))
    }

    private func pipelineName(for pipelineID: UUID) -> String {
        guard let store,
              let pipeline = store.pipelines.first(where: { $0.id == pipelineID })
        else { return localized("Pipeline") }
        let name = pipeline.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? localized("Pipeline") : name
    }

    private func cardName(for pipelineID: UUID, stepIndex: Int) -> String {
        guard let store,
              let pipeline = store.pipelines.first(where: { $0.id == pipelineID }),
              stepIndex >= 0, stepIndex < pipeline.cards.count
        else { return localized("Step %d", stepIndex + 1) }
        let name = pipeline.cards[stepIndex].name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? localized("Step %d", stepIndex + 1) : name
    }
}
