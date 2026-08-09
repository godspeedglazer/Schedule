import AppKit
import Foundation
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let clockStatus = ClockStatusController()
    private let timerStatus = TimerStatusController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        UNUserNotificationCenter.current().delegate = self
        Scheduler.shared.start()
        AccessibilityMonitor.shared.start()
        AppWatchMonitor.shared.start()
        AccessibilityMonitor.shared.onIdleThreshold = { [weak self] idle in
            self?.handleIdle(idle)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(dismissAllNotification(_:)), name: .schedDismissAll, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemTimeDidChange(_:)),
            name: .NSSystemClockDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemTimeDidChange(_:)),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )

        handleCommandLineURLs()
        LoginItemHelper.sync(enabled: ScheduleStore.shared.store.launchAtLogin)

        MainWindowController.shared.showWindow()
        // Create the clock first and the timer second. macOS normally places later
        // status items to the left, giving Sched the preferred [timer] [clock] order
        // while still allowing the user to rearrange them.
        clockStatus.install()
        timerStatus.install()
        FloatingTimerController.shared.startObserving()
    }

    private func installMainMenu() {
        let main = NSMenu()

        let appRoot = NSMenuItem()
        let appMenu = NSMenu(title: "Sched")
        appRoot.submenu = appMenu
        main.addItem(appRoot)
        appMenu.addItem(menuItem("About Sched", action: #selector(showAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("Preferences…", action: #selector(openPreferences), key: ","))
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        appMenu.addItem(servicesItem)
        NSApp.servicesMenu = servicesMenu
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("Hide Sched", action: #selector(hideApp), key: "h"))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem("Quit Sched", action: #selector(quit), key: "q"))

        let editRoot = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editRoot.submenu = editMenu
        main.addItem(editRoot)
        editMenu.addItem(responderItem("Undo", action: Selector(("undo:")), key: "z"))
        let redo = responderItem("Redo", action: Selector(("redo:")), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(responderItem("Cut", action: Selector(("cut:")), key: "x"))
        editMenu.addItem(responderItem("Copy", action: Selector(("copy:")), key: "c"))
        editMenu.addItem(responderItem("Paste", action: Selector(("paste:")), key: "v"))
        editMenu.addItem(responderItem("Select All", action: Selector(("selectAll:")), key: "a"))

        let viewRoot = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        viewRoot.submenu = viewMenu
        main.addItem(viewRoot)
        viewMenu.addItem(menuItem("Plan", action: #selector(openPlan), key: "1"))
        viewMenu.addItem(menuItem("Calendar", action: #selector(openCalendar), key: "2"))
        viewMenu.addItem(menuItem("Timer", action: #selector(openTimer), key: "3"))
        viewMenu.addItem(menuItem("Limits", action: #selector(openLimits), key: "4"))

        let timerRoot = NSMenuItem()
        let timerMenu = NSMenu(title: "Timer")
        timerRoot.submenu = timerMenu
        main.addItem(timerRoot)
        timerMenu.addItem(menuItem("Start 25-Minute Timer", action: #selector(quick25), key: "t"))
        let floating = menuItem("Show Floating Timer", action: #selector(showFloatingTimer), key: "t")
        floating.keyEquivalentModifierMask = [.command, .option]
        timerMenu.addItem(floating)
        timerMenu.addItem(menuItem("Pause or Resume", action: #selector(pauseOrResumeTimer)))
        timerMenu.addItem(menuItem("Add 5 Minutes", action: #selector(addFiveMinutes)))

        let windowRoot = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowRoot.submenu = windowMenu
        main.addItem(windowRoot)
        windowMenu.addItem(responderItem("Minimize", action: Selector(("performMiniaturize:")), key: "m"))
        windowMenu.addItem(responderItem("Zoom", action: Selector(("performZoom:"))))
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func responderItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
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

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func hideApp() { NSApp.hide(nil) }

    @objc private func openPreferences() {
        MainWindowController.shared.showSection(.settings)
        MainWindowController.shared.showWindow()
    }

    @objc private func openPlan() {
        MainWindowController.shared.showSection(.schedule)
        MainWindowController.shared.showWindow()
    }

    @objc private func openCalendar() {
        MainWindowController.shared.showSection(.calendar)
        MainWindowController.shared.showWindow()
    }

    @objc private func openTimer() {
        MainWindowController.shared.showSection(.timer)
        MainWindowController.shared.showWindow()
    }

    @objc private func openLimits() {
        MainWindowController.shared.showSection(.limits)
        MainWindowController.shared.showWindow()
    }

    @objc private func showFloatingTimer() { FloatingTimerController.shared.show() }
    @objc private func pauseOrResumeTimer() { TimerService.shared.pauseOrResume() }
    @objc private func addFiveMinutes() { TimerService.shared.add(minutes: 5) }

    @objc private func openMain() {
        MainWindowController.shared.showWindow()
    }

    @objc private func quick25() {
        _ = TimerService.shared.start(minutes: 25, title: "Focus", level: .focus)
    }

    @objc private func quit() {
        AlarmAudioService.shared.stopAll()
        InterventionManager.shared.dismissAll()
        NSApp.terminate(nil)
    }

    private func handleCommandLineURLs() {
        for arg in CommandLine.arguments.dropFirst() {
            let lower = arg.lowercased()
            guard lower.hasPrefix("sched://") || lower.hasPrefix("keen://") else { continue }
            if let url = URL(string: arg) { URLHandler.handle(url) }
        }
    }

    private func handleIdle(_ seconds: TimeInterval) {
        let minutes = Int(seconds / 60)
        Scheduler.shared.fireNow(
            SchedAlarm(title: "Still here?", note: "Idle ~\(minutes)m.", fireAt: .now, level: .gentle)
        )
        ScheduleStore.shared.setIdleNudge(minutes: nil)
    }

    @objc private func dismissAll() {
        AlarmAudioService.shared.stopAll()
        InterventionManager.shared.dismissAll()
    }

    @objc private func dismissAllNotification(_ notification: Notification) {
        AlarmAudioService.shared.stopAll()
        InterventionManager.shared.dismissAll()
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        Scheduler.shared.handleSystemWake()
        AppWatchMonitor.shared.evaluateNow()
        AccessibilityMonitor.shared.start()
        clockStatus.refreshForSystemTimeChange()
        timerStatus.refreshForSystemTimeChange()
    }

    @objc private func systemTimeDidChange(_ notification: Notification) {
        Scheduler.shared.handleSystemTimeChange()
        clockStatus.refreshForSystemTimeChange()
        timerStatus.refreshForSystemTimeChange()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
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
