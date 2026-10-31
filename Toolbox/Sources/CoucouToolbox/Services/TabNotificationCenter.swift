import Foundation

/// Single entry point for tab-level notifications shown as a notch banner stack
/// while every display is collapsed.
@MainActor
final class TabNotificationCenter {
    var isFullyCollapsed: () -> Bool = { true }
    var onPush: ((NotchNotification) -> Void)?

    func post(_ notification: NotchNotification) {
        guard isFullyCollapsed() else { return }
        onPush?(notification)
    }

    func post(message: String, symbol: String? = nil) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        post(NotchNotification.pipeline(message: trimmed))
    }
}
