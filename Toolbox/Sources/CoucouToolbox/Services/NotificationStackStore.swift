import Foundation

/// Holds a stack of notch notifications with per-item auto-dismiss timers.
@MainActor
final class NotificationStackStore: ObservableObject {
    nonisolated static let maxVisible = 3
    nonisolated static let maxStored = 10
    nonisolated static let defaultDuration: TimeInterval = 4
    nonisolated static let urgentDuration: TimeInterval = 6

    @Published private(set) var items: [NotchNotification] = []

    var overflowCount: Int { max(0, items.count - Self.maxVisible) }
    var visibleCount: Int { min(items.count, Self.maxVisible) }

    /// Called after the last item is dismissed — not after `clear()`.
    var onStackEmpty: (() -> Void)?

    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    func push(_ notification: NotchNotification) {
        let trimmed = notification.message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let key = notification.dedupeKey,
           let index = items.firstIndex(where: { $0.dedupeKey == key }) {
            cancelDismiss(for: items[index].id)
            items.remove(at: index)
        }

        items.insert(notification, at: 0)
        scheduleDismiss(for: notification)
        trimOverflow()
    }

    func dismiss(id: UUID) {
        cancelDismiss(for: id)
        items.removeAll { $0.id == id }
        if items.isEmpty {
            onStackEmpty?()
        }
    }

    func dismissAll() {
        for id in items.map(\.id) {
            cancelDismiss(for: id)
        }
        items.removeAll()
        onStackEmpty?()
    }

    /// Clears the stack without shrinking the panel — used when hover expands.
    func clear() {
        for id in items.map(\.id) {
            cancelDismiss(for: id)
        }
        items.removeAll()
    }

    private func trimOverflow() {
        while items.count > Self.maxStored {
            let removed = items.removeLast()
            cancelDismiss(for: removed.id)
        }
    }

    private func scheduleDismiss(for notification: NotchNotification) {
        let id = notification.id
        let duration = notification.duration
        dismissTasks[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismiss(id: id)
        }
    }

    private func cancelDismiss(for id: UUID) {
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
    }
}
