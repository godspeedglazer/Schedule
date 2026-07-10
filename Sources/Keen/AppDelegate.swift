import AppKit
import Foundation
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let clockStatus = ClockStatusController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        Scheduler.shared.start()
        AccessibilityMonitor.shared.start()
        AppWatchMonitor.shared.start()
        AccessibilityMonitor.shared.onIdleThreshold = { [weak self] idle in
            self?.handleIdle(idle)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(dismissAll), name: .keenDismissAll, object: nil)

        handleCommandLineURLs()
        LoginItemHelper.sync(enabled: ScheduleStore.shared.store.launchAtLogin)

        MainWindowController.shared.showWindow()
        clockStatus.install()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !ScheduleStore.shared.store.headlessWhenClosed
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            MainWindowController.shared.showWindow()
        }
        return true
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open", action: #selector(openMain), keyEquivalent: "")
        menu.addItem(withTitle: "New 25m Timer", action: #selector(quick25), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Dismiss Alerts", action: #selector(dismissAll), keyEquivalent: "")
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        return menu
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { URLHandler.handle(url) }
        MainWindowController.shared.showWindow()
    }

    @objc private func openMain() {
        MainWindowController.shared.showWindow()
    }

    @objc private func quick25() {
        _ = Scheduler.shared.scheduleIn(title: "Focus", minutes: 25, level: .focus)
    }

    @objc private func quit() {
        InterventionManager.shared.dismissAll()
        NSApp.terminate(nil)
    }

    private func handleCommandLineURLs() {
        for arg in CommandLine.arguments.dropFirst() where arg.hasPrefix("keen://") {
            if let url = URL(string: arg) { URLHandler.handle(url) }
        }
    }

    private func handleIdle(_ seconds: TimeInterval) {
        let minutes = Int(seconds / 60)
        Scheduler.shared.fireNow(
            KeenAlarm(title: "Still here?", note: "Idle ~\(minutes)m.", fireAt: .now, level: .gentle)
        )
        ScheduleStore.shared.setIdleNudge(minutes: nil)
    }

    @objc private func dismissAll() {
        InterventionManager.shared.dismissAll()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let request = response.notification.request
        let actionIdentifier = response.actionIdentifier
        let requestIdentifier = request.identifier
        let title = request.content.title
        let body = request.content.body
        let alarmID = request.content.userInfo["alarmID"] as? String
        await MainActor.run {
            NotificationService.shared.handle(
                actionIdentifier: actionIdentifier,
                requestIdentifier: requestIdentifier,
                title: title,
                body: body,
                alarmID: alarmID
            )
        }
    }
}
