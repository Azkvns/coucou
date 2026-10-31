import AppKit
import SwiftUI

enum NotchNotificationSource: Equatable {
    case pipeline
    case calendar(CalendarEventKind)
    case docker
    case digest
}

enum CalendarEventKind: Equatable {
    case eventAdded
    case eventRemoved
    case upcoming(minutes: Int)
    case startingNow
}

enum NotificationAccentStyle: Equatable {
    case neutral, info, success, warning, destructive
}

struct NotificationTint: Equatable {
    var red: Double
    var green: Double
    var blue: Double

    init?(color: NSColor) {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        red = Double(rgb.redComponent)
        green = Double(rgb.greenComponent)
        blue = Double(rgb.blueComponent)
    }

    var swiftUIColor: Color {
        Color(red: red, green: green, blue: blue)
    }
}

struct NotificationAccent: Equatable {
    var style: NotificationAccentStyle
    var tint: NotificationTint?
}

struct NotchNotification: Identifiable, Equatable {
    let id: UUID
    let source: NotchNotificationSource
    let message: String
    let symbol: String
    let accent: NotificationAccent
    let dedupeKey: String?
    var duration: TimeInterval

    var isUrgent: Bool {
        switch source {
        case .calendar(.upcoming(let minutes)): return minutes <= 5
        case .calendar(.startingNow): return true
        case .docker: return false
        case .pipeline: return false
        case .calendar: return false
        case .digest: return false
        }
    }

    init(
        id: UUID = UUID(),
        source: NotchNotificationSource,
        message: String,
        symbol: String,
        accent: NotificationAccent,
        dedupeKey: String? = nil,
        duration: TimeInterval = NotificationStackStore.defaultDuration
    ) {
        self.id = id
        self.source = source
        self.message = message
        self.symbol = symbol
        self.accent = accent
        self.dedupeKey = dedupeKey
        self.duration = duration
    }
}

extension NotchNotification {
    private static let pipelineSymbol = "arrow.triangle.branch"

    static func pipeline(message: String) -> NotchNotification {
        NotchNotification(
            source: .pipeline,
            message: message,
            symbol: pipelineSymbol,
            accent: NotificationAccent(style: .info, tint: nil)
        )
    }

    static func calendar(
        kind: CalendarEventKind,
        title: String,
        calendarColor: NSColor? = nil,
        meetingID: String? = nil
    ) -> NotchNotification {
        let tint = calendarColor.flatMap(NotificationTint.init(color:))
        let identity = meetingID ?? title
        let (message, symbol, style, dedupeKey, duration): (String, String, NotificationAccentStyle, String?, TimeInterval) = {
            switch kind {
            case .eventAdded:
                return (
                    localized("Event added: %@", title),
                    "calendar.badge.plus",
                    .info,
                    nil,
                    NotificationStackStore.defaultDuration
                )
            case .eventRemoved:
                return (
                    localized("Event removed: %@", title),
                    "calendar.badge.minus",
                    .destructive,
                    nil,
                    NotificationStackStore.defaultDuration
                )
            case .upcoming(let minutes):
                return (
                    localized("%@ · in %d min", title, minutes),
                    "bell.fill",
                    minutes <= 5 ? .warning : .info,
                    "calendar:\(identity):upcoming:\(minutes)",
                    NotificationStackStore.defaultDuration
                )
            case .startingNow:
                return (
                    localized("%@ · starting now", title),
                    "video.fill",
                    .success,
                    "calendar:\(identity):starting",
                    NotificationStackStore.urgentDuration
                )
            }
        }()

        let accentStyle: NotificationAccentStyle = {
            if tint != nil, kind != .eventRemoved {
                switch kind {
                case .upcoming(let minutes) where minutes <= 5: return .warning
                case .startingNow: return .success
                default: return .info
                }
            }
            return style
        }()

        return NotchNotification(
            source: .calendar(kind),
            message: message,
            symbol: symbol,
            accent: NotificationAccent(style: accentStyle, tint: tint),
            dedupeKey: dedupeKey,
            duration: duration
        )
    }

    static func calendarPrivateUpcoming(minutes: Int) -> NotchNotification {
        NotchNotification(
            source: .calendar(.upcoming(minutes: minutes)),
            message: localized("Upcoming meeting · in %d min", minutes),
            symbol: "bell.fill",
            accent: NotificationAccent(style: minutes <= 5 ? .warning : .info, tint: nil),
            dedupeKey: "calendar:private:upcoming:\(minutes)",
            duration: NotificationStackStore.defaultDuration
        )
    }

    static func calendarPrivateStartingNow() -> NotchNotification {
        NotchNotification(
            source: .calendar(.startingNow),
            message: localized("Upcoming meeting · starting now"),
            symbol: "video.fill",
            accent: NotificationAccent(style: .success, tint: nil),
            dedupeKey: "calendar:private:starting",
            duration: NotificationStackStore.urgentDuration
        )
    }

    static func digest(message: String) -> NotchNotification {
        NotchNotification(
            source: .digest,
            message: message,
            symbol: "newspaper.fill",
            accent: NotificationAccent(style: .info, tint: nil)
        )
    }

    static func docker(name: String, change: DockerServiceChange) -> NotchNotification? {
        guard let message = DockerBannerCopy.message(name: name, change: change) else {
            return nil
        }

        let presentation: (String, NotificationAccentStyle, String)?
        switch change {
        case .runtime(.running):
            presentation = ("play.fill", .success, "docker.\(name).runtime.running")
        case .runtime(.exited):
            presentation = ("stop.fill", .warning, "docker.\(name).runtime.exited")
        case .healthcheck(.unhealthy):
            presentation = ("heart.slash", .destructive, "docker.\(name).healthcheck.unhealthy")
        case .healthcheck(.healthy):
            presentation = ("heart.fill", .success, "docker.\(name).healthcheck.healthy")
        case .httpHealth(.down):
            presentation = ("wifi.slash", .warning, "docker.\(name).http.down")
        case .httpHealth(.up):
            presentation = ("wifi", .success, "docker.\(name).http.up")
        case .runtime, .healthcheck, .httpHealth:
            presentation = nil
        }
        guard let (symbol, style, dedupeKey) = presentation else { return nil }

        return NotchNotification(
            source: .docker,
            message: message,
            symbol: symbol,
            accent: NotificationAccent(style: style, tint: nil),
            dedupeKey: dedupeKey
        )
    }
}
