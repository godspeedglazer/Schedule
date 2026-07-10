import Foundation

@MainActor
final class ScheduleStore {
    static let shared = ScheduleStore()

    private let url: URL
    private(set) var store: KeenStore
    var onChange: (() -> Void)?
    private var observers: [UUID: () -> Void] = [:]

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Keen", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("schedule.json")
        store = (try? Self.load(from: url)) ?? .empty
    }

    func save() { persist(broadcast: true) }

    private func persist(broadcast: Bool, notifyOnChange: Bool = true) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(store) {
            try? data.write(to: url, options: .atomic)
        }
        if broadcast {
            if notifyOnChange { onChange?() }
            for observer in observers.values { observer() }
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

    func upsert(_ alarm: KeenAlarm, broadcast: Bool = true, notifyOnChange: Bool = true) {
        if let idx = store.alarms.firstIndex(where: { $0.id == alarm.id }) {
            store.alarms[idx] = alarm
        } else {
            store.alarms.append(alarm)
        }
        persist(broadcast: broadcast, notifyOnChange: notifyOnChange)
    }

    func remove(id: UUID, broadcast: Bool = true) {
        store.alarms.removeAll { $0.id == id }
        persist(broadcast: broadcast)
    }

    func setSnoozeMinutes(_ minutes: Int) {
        store.snoozeMinutes = minutes
        persist(broadcast: true)
    }

    func setIdleNudge(minutes: Int?) {
        store.idleMinutesBeforeNudge = minutes
        persist(broadcast: true)
    }

    func replaceAlarms(_ alarms: [KeenAlarm]) {
        store.alarms = alarms
        persist(broadcast: true)
    }

    func replaceStore(_ newStore: KeenStore) {
        store = newStore
        persist(broadcast: true)
    }

    func enabledAlarms() -> [KeenAlarm] {
        store.alarms.filter(\.enabled).sorted { $0.fireAt < $1.fireAt }
    }

    func nextAlarm(after date: Date = .now) -> KeenAlarm? {
        enabledAlarms().first { $0.fireAt > date }
    }

    private static func load(from url: URL) throws -> KeenStore {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(KeenStore.self, from: data)
    }
}
