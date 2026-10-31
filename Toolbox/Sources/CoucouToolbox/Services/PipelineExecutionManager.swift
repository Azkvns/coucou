import Combine
import Foundation

@MainActor
final class PipelineExecutionManager: ObservableObject {
    @Published private(set) var activeCount: Int = 0

    private var runners: [UUID: PipelineRunner] = [:]
    private var cancellables = Set<AnyCancellable>()

    var onRunnerCreated: ((PipelineRunner) -> Void)?

    func runner(for pipelineID: UUID) -> PipelineRunner {
        if let existing = runners[pipelineID] { return existing }
        let runner = PipelineRunner(pipelineID: pipelineID)
        runners[pipelineID] = runner
        runner.objectWillChange
            .sink { [weak self] _ in self?.refreshActiveCount() }
            .store(in: &cancellables)
        onRunnerCreated?(runner)
        return runner
    }

    func isRunning(_ pipelineID: UUID) -> Bool {
        runner(for: pipelineID).isActive
    }

    func stopAll() async {
        for runner in runners.values where runner.isActive {
            runner.stop()
        }
        refreshActiveCount()
    }

    func stopAllImmediately() {
        for runner in runners.values where runner.isActive {
            runner.stopImmediately()
        }
        refreshActiveCount()
    }

    private func refreshActiveCount() {
        let count = runners.values.filter(\.isActive).count
        if activeCount != count {
            activeCount = count
        }
    }
}
