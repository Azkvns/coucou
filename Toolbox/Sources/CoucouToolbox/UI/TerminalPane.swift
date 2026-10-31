import SwiftUI

struct TerminalPane: View {
    @ObservedObject var terminal: TerminalStore
    @Binding var wantsKeyboard: Bool

    var body: some View {
        VStack(spacing: 6) {
            tabStrip
            terminalBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(terminal.tabs) { tab in
                    tabButton(tab)
                }
                Button { terminal.addTab() } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .pointerStyle(.default)
                .help(localized("New Tab"))
            }
            .padding(.horizontal, 6)
        }
        .frame(height: 28)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.surface)
        )
    }

    private func tabButton(_ tab: TerminalTab) -> some View {
        let selected = terminal.selectedTabID == tab.id
        return HStack(spacing: 4) {
            Button {
                terminal.selectTab(tab.id)
            } label: {
                Text(tab.title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? Color.white : Theme.secondary)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .pointerStyle(.default)

            if terminal.tabs.count > 1 {
                Button {
                    terminal.closeTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.tertiary)
                }
                .buttonStyle(.plain)
                .pointerStyle(.default)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(selected ? Theme.surfaceHover : Color.clear)
        )
    }

    @ViewBuilder
    private var terminalBody: some View {
        if wantsKeyboard, let tabID = terminal.selectedTabID {
            if terminal.selectedSessionHasExited {
                TerminalSessionExitedView {
                    terminal.restartSelectedTab()
                }
            } else {
                TerminalHostView(terminal: terminal, tabID: tabID)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.surface)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: 1)
                    )
            }
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.surface)
                Text(localized("Terminal runs on the active display"))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }
}

private struct TerminalSessionExitedView: View {
    let restart: () -> Void

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.surface)
            VStack(spacing: 8) {
                Text(localized("Shell exited"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                Button(localized("Restart"), action: restart)
                    .buttonStyle(NotchButtonStyle(size: 28, prominent: true))
            }
        }
    }
}

struct TerminalCounter: View {
    @ObservedObject var terminal: TerminalStore

    var body: some View {
        if terminal.tabs.count > 1 {
            Text("\(terminal.tabs.count)")
                .font(.system(size: 10, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.tertiary)
        }
    }
}
