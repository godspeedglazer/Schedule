import Foundation

struct TimerSnapshot: Equatable {
    let id: UUID
    let title: String
    let note: String
    let remainingSeconds: Int
    let isPaused: Bool
    let fireAt: Date

    var formattedRemaining: String {
        let seconds = max(0, remainingSeconds)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainder)
            : String(format: "%02d:%02d", minutes, remainder)
    }
}

@MainActor
final class TimerService {
    static let shared = TimerService()

    private var observers: [UUID: () -> Void] = [:]
    private var storeObserver: UUID?

    private init() {
        storeObserver = ScheduleStore.shared.observeChanges { [weak self] in
            self?.notifyObservers()
        }
    }

    func activeTimers(now: Date = .now) -> [SchedAlarm] {
        ScheduleStore.shared.store.alarms
            .filter { alarm in
                guard alarm.isTimer else { return false }
                if alarm.pausedRemainingSeconds != nil { return true }
                return alarm.enabled && alarm.fireAt > now
            }
            .sorted { left, right in
                remainingSeconds(for: left, now: now) < remainingSeconds(for: right, now: now)
            }
    }

    func primaryTimer(now: Date = .now) -> SchedAlarm? {
        activeTimers(now: now).first
    }

    func snapshot(now: Date = .now) -> TimerSnapshot? {
        guard let alarm = primaryTimer(now: now) else { return nil }
        return TimerSnapshot(
            id: alarm.id,
            title: alarm.title,
            note: alarm.note,
            remainingSeconds: remainingSeconds(for: alarm, now: now),
            isPaused: alarm.pausedRemainingSeconds != nil,
            fireAt: alarm.fireAt
        )
    }

    @discardableResult
    func start(
        minutes: Int,
        title: String = "Focus",
        note: String = "Timer complete. Take a breath before the next thing.",
        level: InterventionLevel = .gentle,
        action: SchedAction = .none,
        sound: AlarmSound? = nil
    ) -> SchedAlarm {
        let alarm = Scheduler.shared.scheduleIn(
            title: title,
            note: note,
            minutes: minutes,
            level: level,
            action: action,
            sound: sound
        )
        notifyObservers()
        return alarm
    }

    func pauseOrResume(id: UUID? = nil) {
        guard var alarm = alarmForAction(id: id) else { return }
        if let remaining = alarm.pausedRemainingSeconds {
            alarm.fireAt = Date().addingTimeInterval(TimeInterval(max(1, remaining)))
            alarm.pausedRemainingSeconds = nil
            alarm.enabled = true
        } else {
            alarm.pausedRemainingSeconds = max(1, Int(alarm.fireAt.timeIntervalSinceNow.rounded(.up)))
            alarm.enabled = false
        }
        ScheduleStore.shared.upsert(alarm)
    }

    func add(minutes: Int, id: UUID? = nil) {
        guard minutes != 0, var alarm = alarmForAction(id: id) else { return }
        let delta = minutes * 60
        if let remaining = alarm.pausedRemainingSeconds {
            alarm.pausedRemainingSeconds = max(1, remaining + delta)
        } else {
            alarm.fireAt = alarm.fireAt.addingTimeInterval(TimeInterval(delta))
            if alarm.fireAt <= .now { alarm.fireAt = Date().addingTimeInterval(1) }
        }
        ScheduleStore.shared.upsert(alarm)
    }

    func finish(id: UUID? = nil) {
        guard let alarm = alarmForAction(id: id) else { return }
        AlarmAudioService.shared.stop(alarmID: alarm.id)
        ScheduleStore.shared.remove(id: alarm.id)
    }

    func cancel(id: UUID? = nil) {
        finish(id: id)
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

    private func alarmForAction(id: UUID?) -> SchedAlarm? {
        if let id {
            return ScheduleStore.shared.store.alarms.first { $0.id == id && $0.isTimer }
        }
        return primaryTimer()
    }

    private func remainingSeconds(for alarm: SchedAlarm, now: Date) -> Int {
        alarm.pausedRemainingSeconds ?? max(0, Int(alarm.fireAt.timeIntervalSince(now).rounded(.up)))
    }

    private func notifyObservers() {
        for observer in observers.values { observer() }
    }
}
