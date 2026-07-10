import AppKit
import Foundation

@MainActor
final class Scheduler {
    static let shared = Scheduler()

    private var precisionTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "com.erichspringer.sched.scheduler", qos: .userInteractive)
    private var storeObserver: UUID?
    private var activeControllers: [UUID: InterventionWindowController] = [:]
    var onFire: ((KeenAlarm) -> Void)?

    private init() {
        storeObserver = ScheduleStore.shared.observeChanges { [weak self] in
            self?.reschedule()
        }
    }

    func start() {
        rollForwardMissedAlarms()
        NotificationService.shared.requestAuthorizationIfNeeded()
        reschedule()
    }

    func stop() {
        precisionTimer?.cancel()
        precisionTimer = nil
    }

    func fireNow(_ alarm: KeenAlarm) {
        present(alarm, deliverSystemNotification: true)
    }

    func scheduleIn(title: String, note: String = "", minutes: Int, level: InterventionLevel? = nil, action: KeenAction = .none) -> KeenAlarm {
        let safeMinutes = max(1, min(10_080, minutes))
        let alarm = KeenAlarm(
            title: KeenTextLimits.clean(title, limit: KeenTextLimits.title),
            note: KeenTextLimits.clean(note, limit: KeenTextLimits.note),
            fireAt: Date().addingTimeInterval(TimeInterval(safeMinutes * 60)),
            level: level ?? ScheduleStore.shared.store.defaultLevel,
            action: action,
            isTimer: true
        )
        ScheduleStore.shared.upsert(alarm)
        return alarm
    }

    func scheduleAt(title: String, note: String = "", date: Date, level: InterventionLevel? = nil, repeatDaily: Bool = false, action: KeenAction = .none) -> KeenAlarm {
        let alarm = KeenAlarm(
            title: KeenTextLimits.clean(title, limit: KeenTextLimits.title),
            note: KeenTextLimits.clean(note, limit: KeenTextLimits.note),
            fireAt: date,
            level: level ?? ScheduleStore.shared.store.defaultLevel,
            action: action,
            repeatDaily: repeatDaily
        )
        ScheduleStore.shared.upsert(alarm)
        return alarm
    }

    private func tick() {
        let now = Date()
        for alarm in ScheduleStore.shared.enabledAlarms() where alarm.fireAt <= now.addingTimeInterval(0.05) {
            guard activeControllers[alarm.id] == nil else { continue }
            present(alarm, deliverSystemNotification: false)
            handleRecurrence(alarm)
        }
        reschedule()
    }

    /// Silently roll past-due alarms forward so launch never greys the screen.
    private func rollForwardMissedAlarms() {
        let now = Date()
        let cal = Calendar.current
        for alarm in ScheduleStore.shared.enabledAlarms() where alarm.fireAt <= now {
            if alarm.repeatDaily {
                var next = alarm
                var fireAt = alarm.fireAt
                while fireAt <= now {
                    guard let bumped = cal.date(byAdding: .day, value: 1, to: fireAt) else { break }
                    fireAt = bumped
                }
                next.fireAt = fireAt
                next.enabled = true
                ScheduleStore.shared.upsert(next)
            } else {
                var disabled = alarm
                disabled.enabled = false
                ScheduleStore.shared.upsert(disabled)
            }
        }
    }

    private func present(_ alarm: KeenAlarm, deliverSystemNotification: Bool) {
        if deliverSystemNotification {
            NotificationService.shared.deliverImmediately(alarm)
        } else if ScheduleStore.shared.store.playSoundOnAlert,
                  !ScheduleStore.shared.store.systemNotificationsEnabled {
            NSSound.beep()
        }
        let controller = InterventionWindowController(alarm: alarm) { [weak self] in
            self?.activeControllers.removeValue(forKey: alarm.id)
        }
        activeControllers[alarm.id] = controller
        onFire?(alarm)
    }

    private func handleRecurrence(_ alarm: KeenAlarm) {
        if alarm.repeatDaily {
            var next = alarm
            next.fireAt = Calendar.current.date(byAdding: .day, value: 1, to: alarm.fireAt) ?? alarm.fireAt.addingTimeInterval(86400)
            next.enabled = true
            ScheduleStore.shared.upsert(next)
        } else {
            var disabled = alarm
            disabled.enabled = false
            ScheduleStore.shared.upsert(disabled)
        }
    }

    func dismissAll() {
        for controller in Array(activeControllers.values) {
            controller.forceDismiss()
        }
        activeControllers.removeAll()
    }

    private func reschedule() {
        precisionTimer?.cancel()
        precisionTimer = nil

        NotificationService.shared.syncScheduledNotifications(with: ScheduleStore.shared.enabledAlarms())
        guard let next = ScheduleStore.shared.nextAlarm() else { return }

        let delay = max(0, next.fireAt.timeIntervalSinceNow)
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now() + delay, leeway: .milliseconds(30))
        timer.setEventHandler { [weak self] in
            Task { @MainActor in self?.tick() }
        }
        precisionTimer = timer
        timer.resume()
    }
}
