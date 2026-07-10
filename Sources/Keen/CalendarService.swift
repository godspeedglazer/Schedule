import EventKit
import Foundation

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
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestFullAccessToEvents()
        } catch {
            return false
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
}
