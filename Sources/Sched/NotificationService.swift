import AppKit
import Foundation
import UserNotifications

@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let center = UNUserNotificationCenter.current()
    private let identifierPrefix = "sched.reminder."
    private let categoryIdentifier = "SCHED_REMINDER"
    private let snoozeActionIdentifier = "SCHED_SNOOZE_5"
    private let doneActionIdentifier = "SCHED_DONE"

    private init() {}

    func requestAuthorizationIfNeeded() {
        registerCategories()
        guard ScheduleStore.shared.store.systemNotificationsEnabled else { return }
        center.requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func registerCategories() {
        let snooze = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: "Snooze 5 Minutes",
            options: []
        )
        let done = UNNotificationAction(
            identifier: doneActionIdentifier,
            title: "Done",
            options: []
        )
        let category = UNNotificationCategory(
            identifier: categoryIdentifier,
            actions: [snooze, done],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories([category])
    }

    func syncScheduledNotifications(with alarms: [SchedAlarm]) {
        center.removeAllPendingNotificationRequests()
        guard ScheduleStore.shared.store.systemNotificationsEnabled else { return }

        for alarm in alarms where alarm.fireAt > .now {
            let content = content(for: alarm)
            let components: DateComponents
            if alarm.repeatDaily {
                components = Calendar.current.dateComponents([.hour, .minute, .second], from: alarm.fireAt)
            } else {
                components = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second],
                    from: alarm.fireAt
                )
            }
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: alarm.repeatDaily)
            let request = UNNotificationRequest(
                identifier: identifierPrefix + alarm.id.uuidString,
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    func deliverImmediately(_ alarm: SchedAlarm) {
        guard ScheduleStore.shared.store.systemNotificationsEnabled else { return }
        let request = UNNotificationRequest(
            identifier: identifierPrefix + "instant." + UUID().uuidString,
            content: content(for: alarm),
            trigger: nil
        )
        center.add(request)
    }

    func notificationHealth(_ completion: @escaping @MainActor (String, Bool) -> Void) {
        center.getNotificationSettings { settings in
            let result: (String, Bool)
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                result = ("Notifications are ready", true)
            case .denied:
                result = ("Notifications are blocked in System Settings", false)
            case .notDetermined:
                result = ("Notification permission has not been requested", false)
            @unknown default:
                result = ("Notification status is unavailable", false)
            }
            Task { @MainActor in completion(result.0, result.1) }
        }
    }

    func deliverTest() {
        AlarmAudioService.shared.preview(ScheduleStore.shared.store.defaultSound)
        guard ScheduleStore.shared.store.systemNotificationsEnabled else { return }
        requestAuthorizationIfNeeded()
        let test = SchedAlarm(
            title: "Sched test",
            note: "Sound, Snooze, and Done are ready.",
            fireAt: .now,
            level: .gentle
        )
        let testContent = content(for: test)
        testContent.sound = nil // local preview above prevents a confusing double sound
        center.add(UNNotificationRequest(identifier: identifierPrefix + "test", content: testContent, trigger: nil))
    }

    func handle(
        actionIdentifier: String,
        requestIdentifier: String,
        title: String,
        body: String,
        alarmID: String?
    ) {
        defer { center.removeDeliveredNotifications(withIdentifiers: [requestIdentifier]) }

        switch actionIdentifier {
        case snoozeActionIdentifier:
            let id = alarmID.flatMap(UUID.init(uuidString:))
            var alarm = id.flatMap { alarmID in
                ScheduleStore.shared.store.alarms.first(where: { $0.id == alarmID })
            } ?? SchedAlarm(
                title: title,
                note: body,
                fireAt: .now,
                level: .gentle
            )
            alarm.id = UUID()
            alarm.fireAt = Date().addingTimeInterval(5 * 60)
            alarm.repeatDaily = false
            alarm.enabled = true
            alarm.pausedRemainingSeconds = nil
            alarm.calendarEventIdentifier = nil
            ScheduleStore.shared.upsert(alarm)
            if let id {
                AlarmAudioService.shared.stop(alarmID: id)
                InterventionManager.shared.dismiss(alarmID: id)
            } else {
                InterventionManager.shared.dismissAll()
            }

        case doneActionIdentifier, UNNotificationDismissActionIdentifier:
            if let id = alarmID.flatMap(UUID.init(uuidString:)) {
                AlarmAudioService.shared.stop(alarmID: id)
                InterventionManager.shared.dismiss(alarmID: id)
            } else {
                InterventionManager.shared.dismissAll()
            }

        case UNNotificationDefaultActionIdentifier:
            if let id = alarmID.flatMap(UUID.init(uuidString:)) {
                MainWindowController.shared.showAlarm(id)
            } else {
                MainWindowController.shared.showSection(.schedule)
                MainWindowController.shared.showWindow()
            }

        default:
            break
        }
    }

    private func content(for alarm: SchedAlarm) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = SchedTextLimits.clean(alarm.title, limit: SchedTextLimits.title)
        content.body = alarm.note.isEmpty
            ? "It’s time. Choose Done or Snooze."
            : SchedTextLimits.clean(alarm.note, limit: SchedTextLimits.note)
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = ["alarmID": alarm.id.uuidString]
        switch alarm.level {
        case .gentle:
            content.subtitle = "Reminder"
            content.interruptionLevel = .active
            content.relevanceScore = 0.5
        case .focus:
            content.subtitle = "Focus reminder"
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 0.8
        case .takeover:
            content.subtitle = "Takeover reminder"
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        }
        content.sound = nil
        return content
    }
}
