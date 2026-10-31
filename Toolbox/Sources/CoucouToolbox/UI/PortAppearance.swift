import SwiftUI

enum PortAppearance {
    static func dotColor(for kind: PortKind) -> Color {
        switch kind {
        case .tcpListen:
            return Color.green.opacity(0.9)
        case .tcpEstablished:
            return Color.orange.opacity(0.95)
        case .udp:
            return Color.cyan.opacity(0.85)
        case .other:
            return Theme.tertiary
        }
    }

    static func chipTint(for kind: PortKind) -> Color {
        switch kind {
        case .tcpListen:
            return Color.green.opacity(0.12)
        case .tcpEstablished:
            return Color.orange.opacity(0.12)
        case .udp:
            return Color.cyan.opacity(0.10)
        case .other:
            return .clear
        }
    }

    static func pillLabel(for kind: PortKind, state: String) -> String {
        switch kind {
        case .tcpListen:
            return localized("Listen")
        case .tcpEstablished:
            return localized("Established")
        case .udp:
            return localized("UDP")
        case .other:
            return state
        }
    }

    static func pillForeground(for kind: PortKind) -> Color {
        switch kind {
        case .tcpListen:
            return Color.green.opacity(0.95)
        case .tcpEstablished:
            return Color.orange.opacity(0.95)
        case .udp:
            return Color.cyan.opacity(0.95)
        case .other:
            return Theme.secondary
        }
    }

    static func pillBackground(for kind: PortKind) -> Color {
        switch kind {
        case .tcpListen:
            return Color.green.opacity(0.15)
        case .tcpEstablished:
            return Color.orange.opacity(0.15)
        case .udp:
            return Color.cyan.opacity(0.12)
        case .other:
            return Theme.surfaceHover
        }
    }
}

struct PortKindPill: View {
    let kind: PortKind
    let state: String

    var body: some View {
        Text(PortAppearance.pillLabel(for: kind, state: state))
            .font(.system(size: 9, weight: .semibold).monospaced())
            .foregroundStyle(PortAppearance.pillForeground(for: kind))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(PortAppearance.pillBackground(for: kind)))
    }
}

struct PortLegendPill: View {
    let kind: PortKind

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(PortAppearance.dotColor(for: kind))
                .frame(width: 5, height: 5)
            Text(PortAppearance.pillLabel(for: kind, state: ""))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Theme.tertiary)
        }
    }
}
