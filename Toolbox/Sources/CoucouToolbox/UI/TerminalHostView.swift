import AppKit
import SwiftUI

struct TerminalHostView: NSViewRepresentable {
    @ObservedObject var terminal: TerminalStore
    let tabID: UUID

    func makeCoordinator() -> Coordinator {
        Coordinator(terminal: terminal)
    }

    func makeNSView(context: Context) -> TerminalContainerView {
        let view = TerminalContainerView()
        view.onBoundsChange = { bounds in
            Task { @MainActor in
                context.coordinator.boundsChanged(container: view, bounds: bounds)
            }
        }
        return view
    }

    func updateNSView(_ container: TerminalContainerView, context: Context) {
        terminal.attachView(to: container, tabID: tabID)
    }

    static func dismantleNSView(_ container: TerminalContainerView, coordinator: Coordinator) {
        Task { @MainActor in
            coordinator.terminal.detachViewIfAttached(to: container)
        }
    }

    final class Coordinator {
        let terminal: TerminalStore

        init(terminal: TerminalStore) {
            self.terminal = terminal
        }

        @MainActor
        func boundsChanged(container: TerminalContainerView, bounds: CGRect) {
            terminal.layoutChanged(for: container)
        }
    }
}
