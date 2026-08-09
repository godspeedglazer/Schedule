import Foundation

@MainActor
final class ScheduleStore {
    static let shared = ScheduleStore()

    static let applicationSupportDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Sched", isDirectory: true)

    static let soundsDirectory: URL = applicationSupportDirectory
        .appendingPathComponent("Sounds", isDirectory: true)

    private static let legacyApplicationSupportDirectory: URL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Keen", isDirectory: true)

    private let url: URL
    private(set) var store: SchedStore
    var onChange: (() -> Void)?
    private var observers: [UUID: () -> Void] = [:]

    private init() {
        Self.migrateLegacyApplicationSupportIfNeeded()
        try? FileManager.default.createDirectory(
            at: Self.applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: Self.soundsDirectory,
            withIntermediateDirectories: true
        )
        url = Self.applicationSupportDirectory.appendingPathComponent("schedule.json")
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

    func upsert(_ alarm: SchedAlarm, broadcast: Bool = true, notifyOnChange: Bool = true) {
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

    func replaceAlarms(_ alarms: [SchedAlarm]) {
        store.alarms = alarms
        persist(broadcast: true)
    }

    func replaceStore(_ newStore: SchedStore) {
        store = newStore
        persist(broadcast: true)
    }

    func enabledAlarms() -> [SchedAlarm] {
        store.alarms.filter(\.enabled).sorted { $0.fireAt < $1.fireAt }
    }

    func nextAlarm(after date: Date = .now) -> SchedAlarm? {
        enabledAlarms().first { $0.fireAt > date }
    }


    private static func migrateLegacyApplicationSupportIfNeeded() {
        let fm = FileManager.default
        let legacySchedule = legacyApplicationSupportDirectory.appendingPathComponent("schedule.json")
        let newSchedule = applicationSupportDirectory.appendingPathComponent("schedule.json")
        guard fm.fileExists(atPath: legacySchedule.path), !fm.fileExists(atPath: newSchedule.path) else { return }

        do {
            try fm.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
            try fm.copyItem(at: legacySchedule, to: newSchedule)

            let legacySounds = legacyApplicationSupportDirectory.appendingPathComponent("Sounds", isDirectory: true)
            if fm.fileExists(atPath: legacySounds.path), !fm.fileExists(atPath: soundsDirectory.path) {
                try fm.copyItem(at: legacySounds, to: soundsDirectory)
            }
        } catch {
            // Migration is best-effort. Falling back to the legacy-free defaults is safer
            // than making app launch depend on one stale Application Support file.
        }
    }

    private static func load(from url: URL) throws -> SchedStore {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SchedStore.self, from: data)
    }
}
