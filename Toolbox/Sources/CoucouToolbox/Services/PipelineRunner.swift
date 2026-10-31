import Foundation

@MainActor
final class PipelineRunner: ObservableObject {
    let pipelineID: UUID

    @Published private(set) var phase: PipelinePhase = .idle
    @Published private(set) var outputs: [UUID: PipelineOutput] = [:]
    @Published private(set) var mode: PipelineRunMode?
    @Published private(set) var activeCardID: UUID?

    private var cards: [PipelineCard] = []
    private var process: PipelineProcess?
    private var runTask: Task<Void, Never>?
    private var decisionContinuation: CheckedContinuation<Bool, Never>?

    private static let outputCap = 256 * 1024
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    var isActive: Bool {
        switch phase {
        case .idle: return false
        case .stopping: return true
        case .running, .awaitingDecision: return true
        }
    }

    init(pipelineID: UUID) {
        self.pipelineID = pipelineID
    }

    func runAll(cards: [PipelineCard]) {
        guard !isActive else { return }
        let runnable = cards.filter { !$0.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !runnable.isEmpty else { return }
        self.cards = cards
        mode = .fullPipeline
        resetOutputs(for: cards)
        runTask = Task { await runSteps(from: 0, through: cards.count) }
    }

    func runSingle(cardID: UUID, cards: [PipelineCard]) {
        guard !isActive else { return }
        guard let index = cards.firstIndex(where: { $0.id == cardID }) else { return }
        let command = cards[index].command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        self.cards = cards
        mode = .singleCard(cardID)
        resetOutputs(for: cards)
        runTask = Task { await runSteps(from: index, through: index + 1) }
    }

    func stop() {
        runTask?.cancel()
        runTask = nil
        resumeDecision(with: false)
        phase = .stopping
        let proc = process
        process = nil
        Task {
            await proc?.terminate()
            finish()
        }
    }

    func stopImmediately() {
        runTask?.cancel()
        runTask = nil
        resumeDecision(with: false)
        phase = .stopping
        let proc = process
        process = nil
        Task {
            await proc?.terminate(graceful: false)
            finish()
        }
    }

    func continueAfterError() {
        guard case .awaitingDecision = phase else { return }
        resumeDecision(with: true)
    }

    func abortAfterError() {
        guard case .awaitingDecision = phase else { return }
        resumeDecision(with: false)
    }

    private func runSteps(from startIndex: Int, through endIndex: Int) async {
        for index in startIndex..<endIndex {
            guard !Task.isCancelled else {
                finish()
                return
            }
            let card = cards[index]
            let command = card.command.trimmingCharacters(in: .whitespacesAndNewlines)
            if command.isEmpty { continue }

            phase = .running(stepIndex: index)
            activeCardID = card.id
            prepareOutput(for: card.id)

            let code = await runOneStep(card: card)
            outputs[card.id]?.exitCode = code
            outputs[card.id]?.isRunning = false

            guard !Task.isCancelled else {
                finish()
                return
            }

            if code != 0 {
                phase = .awaitingDecision(stepIndex: index, exitCode: code)
                let shouldContinue = await waitForDecision()
                if !shouldContinue {
                    finish()
                    return
                }
                phase = .running(stepIndex: index + 1)
                continue
            }
        }
        finish()
    }

    private func runOneStep(card: PipelineCard) async -> Int32 {
        let proc = PipelineProcess()
        process = proc
        return await proc.run(
            command: card.command,
            cwd: Self.home,
            onStdout: { [weak self] data in
                self?.appendOutput(cardID: card.id, stdout: data)
            },
            onStderr: { [weak self] data in
                self?.appendOutput(cardID: card.id, stderr: data)
            }
        )
    }

    private func waitForDecision() async -> Bool {
        await withCheckedContinuation { continuation in
            decisionContinuation = continuation
        }
    }

    private func resumeDecision(with value: Bool) {
        decisionContinuation?.resume(returning: value)
        decisionContinuation = nil
    }

    private func finish() {
        process = nil
        runTask = nil
        phase = .idle
        mode = nil
        activeCardID = nil
    }

    private func resetOutputs(for cards: [PipelineCard]) {
        outputs = Dictionary(uniqueKeysWithValues: cards.map { card in
            (card.id, PipelineOutput())
        })
    }

    private func prepareOutput(for cardID: UUID) {
        var output = outputs[cardID] ?? PipelineOutput()
        output.stdout = ""
        output.stderr = ""
        output.exitCode = nil
        output.isRunning = true
        outputs[cardID] = output
    }

    private func appendOutput(cardID: UUID, stdout: Data = Data(), stderr: Data = Data()) {
        guard var output = outputs[cardID] else { return }
        if !stdout.isEmpty {
            output.stdout = Self.capTail(output.stdout + String(decoding: stdout, as: UTF8.self))
        }
        if !stderr.isEmpty {
            output.stderr = Self.capTail(output.stderr + String(decoding: stderr, as: UTF8.self))
        }
        outputs[cardID] = output
    }

    private static func capTail(_ text: String) -> String {
        var utf8 = Array(text.utf8)
        guard utf8.count > outputCap else { return text }
        utf8.removeFirst(utf8.count - outputCap)
        return String(decoding: utf8, as: UTF8.self)
    }
}
