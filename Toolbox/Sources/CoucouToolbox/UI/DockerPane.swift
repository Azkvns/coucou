import SwiftUI

struct DockerPane: View {
    @ObservedObject var store: DockerStore

    @State private var name = ""
    @State private var healthURL = ""

    var body: some View {
        VStack(spacing: 6) {
            content
            addFooter
            if let error = store.lastActionError {
                Text(localized(error))
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }
        }
        .padding(.top, 2)
    }

    @ViewBuilder
    private var content: some View {
        if let error = store.lastError {
            unavailableState(error)
        } else if store.snapshots.isEmpty {
            emptyState
        } else {
            serviceList
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "server.rack")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Theme.tertiary)
            Text(localized("No containers yet"))
                .font(.system(size: 10))
                .foregroundStyle(Theme.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func unavailableState(_ error: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .light))
                .foregroundStyle(Color.yellow.opacity(0.85))
            Text(localized(error))
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondary)
            Button(localized("Retry")) { store.refreshNow() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var serviceList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 5) {
                ForEach(store.snapshots, id: \.spec.id) { snapshot in
                    DockerServiceCard(snapshot: snapshot, store: store)
                }
            }
            .padding(.bottom, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addFooter: some View {
        HStack(spacing: 6) {
            TextField(localized("Name"), text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .tint(Theme.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface))

            TextField(localized("Health URL"), text: $healthURL)
                .textFieldStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.white)
                .tint(Theme.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.surface))

            Button(localized("Add")) { addService() }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(Capsule().fill(Theme.surfaceHover))
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func addService() {
        store.addService(name: name, healthURL: healthURL)
        guard store.lastActionError == nil else { return }
        name = ""
        healthURL = ""
    }
}

private struct DockerServiceCard: View {
    let snapshot: DockerServiceSnapshot
    @ObservedObject var store: DockerStore

    private var isBusy: Bool { store.isBusy(snapshot.spec.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(snapshot.spec.name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                DockerStatePill(
                    title: localized(snapshot.runtime.rawValue.capitalized),
                    color: runtimeColor
                )

                if snapshot.healthcheck != .none {
                    DockerStatePill(
                        title: localized(snapshot.healthcheck.rawValue.capitalized),
                        color: healthcheckColor,
                        symbol: "heart.fill"
                    )
                }

                if snapshot.httpHealth != .none {
                    DockerStatePill(
                        title: localized("HTTP %@", localized(snapshot.httpHealth.rawValue.capitalized)),
                        color: httpColor,
                        symbol: "network"
                    )
                }

                Spacer(minLength: 0)

                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 12, height: 12)
                }

                Button { store.removeService(id: snapshot.spec.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Theme.secondary)
                }
                .buttonStyle(.plain)
                .pointerStyle(.default)
                .disabled(isBusy)
                .help(localized("Remove from catalog"))
            }

            HStack(spacing: 8) {
                Text(portsText)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Theme.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let sizeBytes = snapshot.sizeBytes {
                    Text(localized(
                        "Size: %@",
                        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
                    ))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.tertiary)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)
                actionButtons
            }

            if let error = snapshot.error, !error.isEmpty {
                Text(error)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red.opacity(0.85))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Theme.surface)
        )
    }

    @ViewBuilder
    private var actionButtons: some View {
        ForEach([DockerAction.start, .restart, .kill], id: \.rawValue) { action in
            if action.availability(for: snapshot.runtime) {
                Button(localized(actionTitle(action))) {
                    Task { await store.perform(action, id: snapshot.spec.id) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(action == .kill ? Color.red.opacity(0.85) : .white)
                .disabled(isBusy)
            }
        }
    }

    private var portsText: String {
        guard !snapshot.ports.isEmpty else {
            return localized("No published ports")
        }
        let ports = snapshot.ports
            .map { "\($0.hostIP):\($0.hostPort)/\($0.proto)" }
            .joined(separator: ", ")
        return localized("Ports: %@", ports)
    }

    private func actionTitle(_ action: DockerAction) -> String {
        switch action {
        case .start: return "Start"
        case .restart: return "Restart"
        case .kill: return "Kill"
        }
    }

    private var runtimeColor: Color {
        switch snapshot.runtime {
        case .running: return .green
        case .restarting: return .yellow
        case .exited, .dead, .missing: return .red
        case .paused, .created: return .yellow
        }
    }

    private var healthcheckColor: Color {
        switch snapshot.healthcheck {
        case .healthy: return .green
        case .starting: return .yellow
        case .unhealthy: return .red
        case .none: return Theme.tertiary
        }
    }

    private var httpColor: Color {
        switch snapshot.httpHealth {
        case .up: return .green
        case .degraded: return .yellow
        case .down: return .red
        case .none: return Theme.tertiary
        }
    }
}

private struct DockerStatePill: View {
    let title: String
    let color: Color
    var symbol: String?

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 7, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 8, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(color.opacity(0.9))
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.12)))
    }
}
