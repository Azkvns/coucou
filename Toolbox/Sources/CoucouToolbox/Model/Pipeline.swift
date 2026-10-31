import Foundation

struct PipelineCard: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var command: String

    init(id: UUID = UUID(), name: String = "", command: String = "") {
        self.id = id
        self.name = name
        self.command = command
    }
}

struct Pipeline: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var cards: [PipelineCard]

    init(id: UUID = UUID(), name: String, cards: [PipelineCard] = []) {
        self.id = id
        self.name = name
        self.cards = cards
    }
}

struct PipelinesDocument: Codable, Equatable {
    var pipelines: [Pipeline]
    var selectedPipelineID: UUID?

    static let empty = PipelinesDocument(pipelines: [], selectedPipelineID: nil)
}
