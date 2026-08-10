import EventKit
import Foundation

// Lightweight draft model used by the editor UI
struct CalendarEventDraft {
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var calendarIdentifier: String?
    var location: String
    var notes: String
}

@MainActor
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()
    var onChange: (() -> Void)?

    private init() {
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onChange?() }
        }
    }

    var hasAccess: Bool {
        if #available(macOS 14, *) {
            return EKEventStore.authorizationStatus(for: .event) == .fullAccess
        } else {
            return EKEventStore.authorizationStatus(for: .event) == .authorized
        }
    }

    func requestAccess() async -> Bool {
        if #available(macOS 14, *) {
            do {
                return try await store.requestFullAccessToEvents()
            } catch {
                return false
            }
        } else {
            return await withCheckedContinuation { cont in
                store.requestAccess(to: .event) { granted, _ in
                    cont.resume(returning: granted)
                }
            }
        }
    }

    func events(on date: Date) -> [EKEvent] {
        guard hasAccess else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }

    // MARK: - Convenience helpers used by UI

    var defaultCalendarIdentifier: String? {
        if let defaultCal = store.defaultCalendarForNewEvents {
            return defaultCal.calendarIdentifier
        }
        return store.calendars(for: .event).first?.calendarIdentifier
    }

    func writableCalendars() -> [EKCalendar] {
        store.calendars(for: .event).filter { $0.allowsContentModifications }
    }

    func createEvent(_ draft: CalendarEventDraft) throws -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = draft.title
        event.startDate = draft.startDate
        event.endDate = draft.endDate
        event.isAllDay = draft.isAllDay
        event.location = draft.location
        event.notes = draft.notes

        if let identifier = draft.calendarIdentifier,
           let cal = store.calendar(withIdentifier: identifier) {
            event.calendar = cal
        } else if let defaultID = defaultCalendarIdentifier, let cal = store.calendar(withIdentifier: defaultID) {
            event.calendar = cal
        } else if let firstWritable = writableCalendars().first {
            event.calendar = firstWritable
        } else {
            // fallback to any calendar
            event.calendar = store.calendars(for: .event).first
        }

        try store.save(event, span: .thisEvent)
        return event
    }
}
