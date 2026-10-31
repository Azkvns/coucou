import Combine
import Foundation

/// Observes calendar changes and posts notch notifications while collapsed.
@MainActor
final class CalendarNotificationObserver {
    private static let upcomingThresholds = [15, 5, 1]

    private weak var store: CalendarStore?
    private let center: TabNotificationCenter
    private let visibility: TabVisibility
    private unowned let privacy: PrivacyMode

    private var previousMeetings: [String: CalendarStore.Meeting] = [:]
    private var notifiedKeys = Set<String>()
    private var hasInitialSnapshot = false
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    init(center: TabNotificationCenter, visibility: TabVisibility, privacy: PrivacyMode) {
        self.center = center
        self.visibility = visibility
        self.privacy = privacy
    }

    func install(store: CalendarStore) {
        self.store = store
        store.$meetings
            .sink { [weak self] meetings in
                self?.handleMeetings(meetings)
            }
            .store(in: &cancellables)

        store.$access
            .removeDuplicates()
            .sink { [weak self] access in
                guard let self else { return }
                if access == .granted {
                    startTimerIfNeeded()
                } else {
                    stopTimer()
                }
            }
            .store(in: &cancellables)

        visibility.objectWillChange
            .sink { [weak self] _ in
                self?.startTimerIfNeeded()
            }
            .store(in: &cancellables)

        if store.access == .granted {
            startTimerIfNeeded()
        }
    }

    func teardown() {
        cancellables.removeAll()
        stopTimer()
        previousMeetings.removeAll()
        notifiedKeys.removeAll()
        hasInitialSnapshot = false
    }

    private func handleMeetings(_ meetings: [CalendarStore.Meeting]) {
        let current = Dictionary(
            meetings.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        if !hasInitialSnapshot {
            previousMeetings = current
            hasInitialSnapshot = true
            return
        }

        guard visibility.isEnabled(.calendar), store?.access == .granted else {
            previousMeetings = current
            return
        }

        for (id, meeting) in current where previousMeetings[id] == nil {
            postAdded(meeting)
        }
        for (id, meeting) in previousMeetings where current[id] == nil {
            postRemoved(meeting)
        }
        previousMeetings = current
    }

    private func startTimerIfNeeded() {
        stopTimer()
        guard visibility.isEnabled(.calendar), store?.access == .granted else { return }

        tickUpcoming()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tickUpcoming() }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tickUpcoming() {
        guard visibility.isEnabled(.calendar),
              store?.access == .granted,
              let store
        else { return }

        let now = Date()
        let hidden = privacy.hides(.calendar, "calendar")

        for meeting in store.meetings where meeting.end > now {
            if meeting.isRunning {
                let key = "\(meeting.id):starting"
                guard !notifiedKeys.contains(key) else { continue }
                notifiedKeys.insert(key)
                if hidden {
                    center.post(NotchNotification.calendarPrivateStartingNow())
                } else {
                    center.post(NotchNotification.calendar(
                        kind: .startingNow,
                        title: displayTitle(for: meeting),
                        calendarColor: meeting.calendarColor,
                        meetingID: meeting.id
                    ))
                }
                continue
            }

            let minutesUntil = Int((meeting.start.timeIntervalSince(now) / 60).rounded(.up))
            for threshold in Self.upcomingThresholds {
                let key = "\(meeting.id):upcoming:\(threshold)"
                guard notifiedKeys.contains(key) else { continue }
                if minutesUntil > threshold { notifiedKeys.remove(key) }
            }

            guard Self.upcomingThresholds.contains(minutesUntil) else { continue }

            let key = "\(meeting.id):upcoming:\(minutesUntil)"
            guard !notifiedKeys.contains(key) else { continue }
            notifiedKeys.insert(key)

            if hidden {
                center.post(NotchNotification.calendarPrivateUpcoming(minutes: minutesUntil))
            } else {
                center.post(NotchNotification.calendar(
                    kind: .upcoming(minutes: minutesUntil),
                    title: displayTitle(for: meeting),
                    calendarColor: meeting.calendarColor,
                    meetingID: meeting.id
                ))
            }
        }
    }

    private func postAdded(_ meeting: CalendarStore.Meeting) {
        guard !privacy.hides(.calendar, "calendar") else { return }
        center.post(NotchNotification.calendar(
            kind: .eventAdded,
            title: displayTitle(for: meeting),
            calendarColor: meeting.calendarColor
        ))
    }

    private func postRemoved(_ meeting: CalendarStore.Meeting) {
        guard !privacy.hides(.calendar, "calendar") else { return }
        center.post(NotchNotification.calendar(
            kind: .eventRemoved,
            title: displayTitle(for: meeting),
            calendarColor: meeting.calendarColor
        ))
    }

    private func displayTitle(for meeting: CalendarStore.Meeting) -> String {
        let title = meeting.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? localized("Untitled") : title
    }
}
