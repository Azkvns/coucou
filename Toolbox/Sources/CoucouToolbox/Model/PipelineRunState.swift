import Foundation

enum PipelinePhase: Equatable {
    case idle
    case running(stepIndex: Int)
    case awaitingDecision(stepIndex: Int, exitCode: Int32)
    case stopping
}

struct PipelineOutput: Equatable {
    var stdout: String = ""
    var stderr: String = ""
    var exitCode: Int32?
    var isRunning: Bool = false
}

enum PipelineRunMode: Equatable {
    case fullPipeline
    case singleCard(UUID)
}
