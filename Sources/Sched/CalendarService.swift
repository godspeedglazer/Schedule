import EventKit
import Foundation

struct CalendarEventDraft {
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var calendarIdentifier: String?
    var location: String
    var notes: String
}

struct CalendarChoice: Equatable {
    let identifier: String
    let title: String
}

enum CalendarServiceError: LocalizedError {
    case accessRequired
    case noWritableCalendar
    case eventUnavailable

    var errorDescription: String? {
        switch self {
        case .accessRequired:
            return "Sched needs Calendar access before it can create or read events."
        case .noWritableCalendar:
            return "No writable Calendar is available for this event."
        case .eventUnavailable:
            return "That Calendar event is no longer available."
        }
    }
}

@MainActor
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()
    private var observers: [UUID: () -> Void] = [:]
    private var eventStoreChangeObserver: NSObjectProtocol?

    private init() {
        eventStoreChangeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.notifyObservers() }
        }
    }

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        do {
            let granted = try await store.requestFullAccessToEvents()
            if granted { notifyObservers() }
            return granted
        } catch {
            return false
        }
    }

    @discardableResult
    func observeChanges(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    func refresh() {
        store.refreshSourcesIfNecessary()
        notifyObservers()
    }

    func events(on date: Date) -> [EKEvent] {
        guard hasAccess else { return [] }
        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { left, right in
            if left.isAllDay != right.isAllDay { return left.isAllDay && !right.isAllDay }
            return left.startDate < right.startDate
        }
    }

    func event(identifier: String) -> EKEvent? {
        guard hasAccess else { return nil }
        return store.event(withIdentifier: identifier)
    }

    func writableCalendars() -> [CalendarChoice] {
        guard hasAccess else { return [] }
        return store.calendars(for: .event)
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { CalendarChoice(identifier: $0.calendarIdentifier, title: $0.title) }
    }

    var defaultCalendarIdentifier: String? {
        guard hasAccess else { return nil }
        return store.defaultCalendarForNewEvents?.calendarIdentifier
    }

    @discardableResult
    func createEvent(_ draft: CalendarEventDraft) throws -> EKEvent {
        guard hasAccess else { throw CalendarServiceError.accessRequired }

        let calendar: EKCalendar?
        if let identifier = draft.calendarIdentifier,
           let selected = store.calendar(withIdentifier: identifier),
           selected.allowsContentModifications {
            calendar = selected
        } else {
            calendar = store.defaultCalendarForNewEvents
        }
        guard let calendar, calendar.allowsContentModifications else {
            throw CalendarServiceError.noWritableCalendar
        }

        let event = EKEvent(eventStore: store)
        event.title = SchedTextLimits.clean(draft.title, limit: SchedTextLimits.title)
        if draft.isAllDay {
            let systemCalendar = Calendar.autoupdatingCurrent
            let start = systemCalendar.startOfDay(for: draft.startDate)
            event.startDate = start
            event.endDate = systemCalendar.date(byAdding: .day, value: 1, to: start)
                ?? start.addingTimeInterval(86_400)
        } else {
            event.startDate = draft.startDate
            event.endDate = max(draft.endDate, draft.startDate.addingTimeInterval(60))
        }
        event.isAllDay = draft.isAllDay
        event.calendar = calendar
        event.location = draft.location.trimmingCharacters(in: .whitespacesAndNewlines)
        event.notes = SchedTextLimits.clean(draft.notes, limit: SchedTextLimits.note)
        try store.save(event, span: .thisEvent, commit: true)
        notifyObservers()
        return event
    }

    private func notifyObservers() {
        for observer in observers.values { observer() }
    }
}
