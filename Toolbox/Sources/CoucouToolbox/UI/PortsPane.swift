import AppKit
import SwiftUI

struct PortsPane: View {
    @ObservedObject var ports: PortStore
    @State private var selected: PortBinding?

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            if let selected {
                detailView(selected)
            } else {
                gridView
                footer
            }
        }
        .padding(.top, 2)
        .onChange(of: ports.displayedBindings) { _, displayed in
            guard let selected else { return }
            if !displayed.contains(where: { $0.id == selected.id }) {
                self.selected = nil
            } else if let updated = displayed.first(where: { $0.id == selected.id }) {
                self.selected = updated
            }
        }
    }

    // MARK: - Grid

    @ViewBuilder
    private var gridView: some View {
        if let lastError = ports.lastError {
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Color.yellow.opacity(0.85))
                Text(lastError)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondary)
                Button(localized("Retry")) { ports.refreshNow() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if ports.displayedBindings.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "network")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.tertiary)
                Text(emptyMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 6) {
                legendRow
                ScrollView(showsIndicators: false) {
                    FlowLayout(spacing: 6) {
                        ForEach(ports.displayedBindings) { binding in
                            PortChip(
                                binding: binding,
                                ports: ports,
                                isNew: ports.isNew(binding)
                            ) {
                                selected = binding
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        if let killError = ports.killError {
            Text(killError)
                .font(.system(size: 10))
                .foregroundStyle(Color.red.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }

    private var legendRow: some View {
        HStack(spacing: 10) {
            PortLegendPill(kind: .tcpListen)
            PortLegendPill(kind: .tcpEstablished)
            PortLegendPill(kind: .udp)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyMessage: String {
        switch ports.stateFilter {
        case .listen:
            return localized("Nothing listening")
        case .established:
            return localized("No established connections")
        case .all:
            return localized("No open ports")
        }
    }

    // MARK: - Detail

    private func detailView(_ binding: PortBinding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Button { selected = nil } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                        Text(localized("Back"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                PortKindPill(kind: binding.kind, state: binding.state)
            }

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow(localized("Process"), "\(binding.processName) · \(binding.pid)")
                    if let path = binding.executablePath, !path.isEmpty {
                        detailActionRow(
                            label: localized("Path"),
                            value: path,
                            monospaced: true,
                            copyValue: path,
                            revealPath: path
                        )
                    }
                    if let commandLine = binding.commandLine, !commandLine.isEmpty {
                        detailActionRow(
                            label: localized("Command"),
                            value: commandLine,
                            monospaced: true,
                            copyValue: commandLine,
                            revealPath: nil
                        )
                    }
                    detailRow(
                        localized("Socket"),
                        "\(binding.proto) · \(binding.address):\(binding.port) · \(binding.state)"
                    )
                    detailActionRow(
                        label: localized("Address"),
                        value: localhostAddress(for: binding),
                        monospaced: true,
                        copyValue: localhostAddress(for: binding),
                        revealPath: nil
                    )
                    detailRow(
                        localized("Discovered"),
                        Self.relativeFormatter.localizedString(for: binding.firstSeenAt, relativeTo: Date())
                    )
                    if let startedAt = binding.processStartedAt {
                        detailRow(
                            localized("Process started"),
                            Self.relativeFormatter.localizedString(for: startedAt, relativeTo: Date())
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Button {
                ports.terminate(binding)
            } label: {
                Text(localized("Kill Process"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Theme.surfaceHover))
            }
            .buttonStyle(.plain)

            if let killError = ports.killError {
                Text(killError)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red.opacity(0.85))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func localhostAddress(for binding: PortBinding) -> String {
        let host: String
        if binding.address == "*" || binding.address.isEmpty {
            host = "localhost"
        } else if binding.address.hasPrefix("[") {
            host = binding.address
        } else {
            host = binding.address
        }
        return "\(host):\(binding.port)"
    }

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.tertiary)
            Text(value)
                .font(.system(size: 11, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .lineLimit(monospaced ? 4 : 2)
                .truncationMode(monospaced ? .middle : .tail)
        }
    }

    private func detailActionRow(
        label: String,
        value: String,
        monospaced: Bool,
        copyValue: String,
        revealPath: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
                Spacer(minLength: 0)
                Button(localized("Copy")) {
                    copyToPasteboard(copyValue)
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.secondary)
                if let revealPath {
                    Button(localized("Reveal")) {
                        revealInFinder(revealPath)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.secondary)
                }
            }
            Text(value)
                .font(.system(size: 11, design: monospaced ? .monospaced : .default))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .lineLimit(monospaced ? 4 : 2)
                .truncationMode(monospaced ? .middle : .tail)
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func revealInFinder(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 6) {
            FilterToggle(
                title: ports.ownerFilter == .mine ? localized("Mine") : localized("All"),
                isSelected: true
            ) {
                ports.ownerFilter = ports.ownerFilter == .mine ? .all : .mine
            }

            FilterToggle(
                title: stateFilterTitle,
                isSelected: true
            ) {
                ports.stateFilter = nextStateFilter
            }

            FilterToggle(
                title: sortOrderTitle,
                isSelected: true
            ) {
                ports.sortOrder = nextSortOrder
            }

            FilterToggle(
                title: protoFilterTitle,
                isSelected: true
            ) {
                ports.protoFilter = nextProtoFilter
            }

            if ports.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.55)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var stateFilterTitle: String {
        switch ports.stateFilter {
        case .listen: return localized("Listen")
        case .established: return localized("Established")
        case .all: return localized("All")
        }
    }

    private var nextStateFilter: PortStateFilter {
        switch ports.stateFilter {
        case .listen: return .established
        case .established: return .all
        case .all: return .listen
        }
    }

    private var sortOrderTitle: String {
        switch ports.sortOrder {
        case .newestFirst: return localized("Newest")
        case .oldestFirst: return localized("Oldest")
        case .portNumber: return localized("Port #")
        case .processName: return localized("By name")
        }
    }

    private var nextSortOrder: PortSortOrder {
        switch ports.sortOrder {
        case .newestFirst: return .oldestFirst
        case .oldestFirst: return .portNumber
        case .portNumber: return .processName
        case .processName: return .newestFirst
        }
    }

    private var protoFilterTitle: String {
        switch ports.protoFilter {
        case .all: return localized("All")
        case .tcp: return localized("TCP")
        case .udp: return localized("UDP")
        }
    }

    private var nextProtoFilter: PortProtoFilter {
        switch ports.protoFilter {
        case .all: return .tcp
        case .tcp: return .udp
        case .udp: return .all
        }
    }
}

private struct PortChip: View {
    let binding: PortBinding
    @ObservedObject var ports: PortStore
    let isNew: Bool
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(PortAppearance.dotColor(for: binding.kind))
                .frame(width: 6, height: 6)

            Text("\(binding.port)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text("·")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.tertiary)

            Text(binding.processName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 72, alignment: .leading)

            if isNew {
                Text(localized("New"))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.yellow.opacity(0.95))
            }

            Button {
                ports.terminate(binding)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.secondary)
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.plain)
            .pointerStyle(.default)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(hovering ? Theme.surfaceHover : Theme.surface)
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(PortAppearance.chipTint(for: binding.kind))
                }
        }
        .overlay {
            if isNew {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.yellow.opacity(0.5), lineWidth: 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .onHover { hovering = $0 }
        .onTapGesture { onSelect() }
        .animation(Theme.contentAnimation, value: hovering)
    }
}

private struct FilterToggle: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isSelected ? .white : Theme.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isSelected ? Theme.surfaceHover : Theme.surface)
                )
        }
        .buttonStyle(.plain)
    }
}

/// Chips of different widths laid out left-to-right with wrap. A grid hands
/// every cell the same column width, which fights intrinsic chip sizing and
/// makes them draw on top of each other.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }
    }
}
