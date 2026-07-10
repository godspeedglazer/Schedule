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
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
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

    func syncScheduledNotifications(with alarms: [KeenAlarm]) {
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

    func deliverImmediately(_ alarm: KeenAlarm) {
        guard ScheduleStore.shared.store.systemNotificationsEnabled else {
            if ScheduleStore.shared.store.playSoundOnAlert { NSSound.beep() }
            return
        }
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
                let soundReady = settings.soundSetting == .enabled
                result = (soundReady ? "Notifications and sound are ready" : "Notifications allowed · sound is off in System Settings", soundReady)
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
        playLocalSound()
        guard ScheduleStore.shared.store.systemNotificationsEnabled else { return }
        requestAuthorizationIfNeeded()
        let test = KeenAlarm(
            title: "Sched test",
            note: "Sound, Snooze, and Done are ready.",
            fireAt: .now,
            level: .gentle
        )
        let testContent = content(for: test)
        testContent.sound = nil // local preview above prevents a confusing double sound
        center.add(UNNotificationRequest(identifier: identifierPrefix + "test", content: testContent, trigger: nil))
    }

    private func playLocalSound() {
        if let sound = NSSound(named: NSSound.Name("Glass")) { sound.play() }
        else { NSSound.beep() }
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
            } ?? KeenAlarm(
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
            ScheduleStore.shared.upsert(alarm)
            InterventionManager.shared.dismissAll()

        case doneActionIdentifier, UNNotificationDismissActionIdentifier:
            InterventionManager.shared.dismissAll()

        case UNNotificationDefaultActionIdentifier:
            MainWindowController.shared.showSection(.schedule)
            MainWindowController.shared.showWindow()

        default:
            break
        }
    }

    private func content(for alarm: KeenAlarm) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = KeenTextLimits.clean(alarm.title, limit: KeenTextLimits.title)
        content.body = alarm.note.isEmpty
            ? "It’s time. Choose Done or Snooze."
            : KeenTextLimits.clean(alarm.note, limit: KeenTextLimits.note)
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = ["alarmID": alarm.id.uuidString]
        if ScheduleStore.shared.store.playSoundOnAlert {
            content.sound = .default
        }
        return content
    }
}
