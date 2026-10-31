import Foundation

// The profile does not render eyes; AgentTask's display-only field still needs a type.
enum EyeShape: String { case test }

@main
struct ForkProfileTests {
    static func main() {
        let providers = ChatProvider.allCases
        precondition(providers.first == .openai)
        precondition(providers.contains(.cursor))
        precondition(!providers.contains(.anthropic))
        // Legacy preferences remain decodable, so AppState can migrate them.
        precondition(ChatProvider(rawValue: "anthropic") == .anthropic)
        let ids = Set(PillCatalog.available.map(\.id))
        precondition(!ids.contains("integration_claude"))
        precondition(!ids.contains("agent_claude-desktop"))
        precondition(!ids.contains("ai_anthropic"))
        precondition(ids.contains(PillCatalog.defaultMainPillId))
        #if APPSTORE
        precondition(PillCatalog.defaultMainPillId == "agent_cursor")
        precondition(!ids.contains("integration_toolbox"))
        #else
        precondition(PillCatalog.defaultMainPillId == "agent_codex")
        precondition(ids.contains("integration_toolbox"))
        #endif
        print("Fork profile checks passed")
    }
}
