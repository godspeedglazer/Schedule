import AppKit
import EventKit

@MainActor
final class ClockStatusController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var timer: Timer?
    private var storeObserver: UUID?
    private var calendarObserver: UUID?

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Sched.ClockStatusItem"
        statusItem = item

        statusMenu.delegate = self
        statusMenu.autoenablesItems = false
        item.menu = statusMenu

        storeObserver = ScheduleStore.shared.observeChanges { [weak self] in self?.refresh() }
        calendarObserver = CalendarService.shared.observeChanges { [weak self] in self?.refresh() }
        refresh()
    }

    func refreshForSystemTimeChange() { refresh() }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func refresh() {
        guard let item = statusItem, let button = item.button else { return }
        let preferences = ScheduleStore.shared.store
        item.isVisible = preferences.menuBarClockEnabled
        guard preferences.menuBarClockEnabled else {
            stopRefreshTimer()
            return
        }
        configureRefreshTimer(for: preferences)

        button.image = preferences.menuBarShowIcon ? statusIcon() : nil
        button.image?.isTemplate = true

        var components: [String] = []
        if preferences.menuBarShowDate {
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("E d")
            components.append(formatter.string(from: .now))
        }
        if preferences.menuBarShowTime {
            components.append(SchedTimeFormat.string(from: .now, includeSeconds: preferences.menuBarShowSeconds))
        }

        let title = components.joined(separator: "  ")
        button.title = title.isEmpty ? "" : " " + title
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeft
        button.font = preferences.menuBarShowSeconds
            ? NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : NSFont.menuBarFont(ofSize: 0)
        item.length = title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength

        if let next = ScheduleStore.shared.enabledAlarms().first(where: { !$0.isTimer }) {
            button.toolTip = "Next: \(next.title) at \(SchedTimeFormat.string(from: next.fireAt))"
        } else {
            button.toolTip = "Sched Calendar"
        }
    }

    private func configureRefreshTimer(for preferences: SchedStore) {
        timer?.invalidate()
        let now = Date()
        let nextFire: Date
        if preferences.menuBarShowSeconds {
            nextFire = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970) + 1)
        } else {
            let calendar = Calendar.autoupdatingCurrent
            let nextMinute = now.addingTimeInterval(60)
            nextFire = calendar.date(bySetting: .second, value: 0, of: nextMinute) ?? nextMinute
        }
        let refreshTimer = Timer(fire: nextFire, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.timer = nil
                self?.refresh()
            }
        }
        timer = refreshTimer
        RunLoop.main.add(refreshTimer, forMode: .common)
    }

    private func stopRefreshTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()
        statusMenu.minimumWidth = 292

        let calendarItem = NSMenuItem()
        calendarItem.view = ClockCalendarMenuView { [weak self] date in
            self?.statusMenu.cancelTracking()
            MainWindowController.shared.showCalendar(date: date)
        }
        statusMenu.addItem(calendarItem)

        let dateFormatter = DateFormatter()
        dateFormatter.locale = .autoupdatingCurrent
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none
        let today = NSMenuItem(title: dateFormatter.string(from: .now), action: nil, keyEquivalent: "")
        today.isEnabled = false
        statusMenu.addItem(today)
        statusMenu.addItem(.separator())

        addUpcomingSection()
        addDailiesSection()
        addAllRemindersSection()
        addCalendarTodaySection()

        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem("New Event…", symbol: "calendar.badge.plus", action: #selector(newEvent)))
        statusMenu.addItem(menuItem("New Reminder…", symbol: "bell.badge.plus", action: #selector(newReminder)))
        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem("Open Calendar", symbol: "calendar", action: #selector(openCalendar)))
        statusMenu.addItem(menuItem("Preferences", symbol: "gearshape", action: #selector(openSettings)))

        let dismiss = menuItem("Dismiss Alerts", symbol: "bell.slash", action: #selector(dismissAlerts))
        dismiss.isEnabled = InterventionManager.shared.hasActive
        statusMenu.addItem(dismiss)

        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem("Quit Sched", action: #selector(quit)))
    }

    private func addUpcomingSection() {
        let upcoming = ScheduleStore.shared.enabledAlarms()
            .filter { !$0.isTimer && !$0.repeatDaily && $0.fireAt >= .now }
            .prefix(4)

        let heading = disabledItem("UP NEXT")
        statusMenu.addItem(heading)
        if upcoming.isEmpty {
            statusMenu.addItem(disabledItem("No one-time reminders ahead"))
        } else {
            for alarm in upcoming { statusMenu.addItem(alarmMenuItem(alarm)) }
        }
    }

    private func addDailiesSection() {
        let dailies = ScheduleStore.shared.store.alarms
            .filter { $0.enabled && !$0.isTimer && $0.repeatDaily }
            .sorted { left, right in
                let calendar = Calendar.autoupdatingCurrent
                let l = calendar.dateComponents([.hour, .minute], from: left.fireAt)
                let r = calendar.dateComponents([.hour, .minute], from: right.fireAt)
                let leftMinutes = (l.hour ?? 0) * 60 + (l.minute ?? 0)
                let rightMinutes = (r.hour ?? 0) * 60 + (r.minute ?? 0)
                return leftMinutes < rightMinutes
            }
        guard !dailies.isEmpty else { return }

        let root = NSMenuItem(title: "Dailies", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "repeat", accessibilityDescription: nil)
        let submenu = NSMenu(title: "Dailies")
        for alarm in dailies { submenu.addItem(alarmMenuItem(alarm)) }
        submenu.addItem(.separator())
        let manage = NSMenuItem(title: "Manage Dailies…", action: #selector(openPlan), keyEquivalent: "")
        manage.target = self
        submenu.addItem(manage)
        root.submenu = submenu
        statusMenu.addItem(root)
    }

    private func addAllRemindersSection() {
        let alarms = ScheduleStore.shared.enabledAlarms().filter { !$0.isTimer }
        guard !alarms.isEmpty else { return }

        let root = NSMenuItem(title: "All Reminders", action: nil, keyEquivalent: "")
        root.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: nil)
        let submenu = NSMenu(title: "All Reminders")
        for alarm in alarms {
            let item = alarmMenuItem(alarm)
            let context = SchedTimeFormat.dateContext(from: alarm.fireAt)
            item.title = "\(context) · \(Self.alarmMenuTitle(alarm))"
            submenu.addItem(item)
        }
        root.submenu = submenu
        statusMenu.addItem(root)
    }

    private func addCalendarTodaySection() {
        statusMenu.addItem(.separator())
        statusMenu.addItem(disabledItem("TODAY IN CALENDAR"))

        guard CalendarService.shared.hasAccess else {
            statusMenu.addItem(menuItem("Enable Calendar Access…", symbol: "calendar.badge.plus", action: #selector(requestCalendarAccess)))
            return
        }

        let events = CalendarService.shared.events(on: .now)
        if events.isEmpty {
            statusMenu.addItem(disabledItem("No Calendar events today"))
            return
        }

        for event in events.prefix(5) {
            let time = event.isAllDay ? "All day" : SchedTimeFormat.string(from: event.startDate)
            let item = NSMenuItem(
                title: "\(time)  \(Self.compact(event.title ?? "Calendar event", limit: 24))",
                action: #selector(openCalendarEvent(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = event.startDate
            item.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
            item.toolTip = [event.title, event.location, event.calendar.title]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            statusMenu.addItem(item)
        }
        if events.count > 5 {
            statusMenu.addItem(menuItem("\(events.count - 5) more…", action: #selector(openCalendar)))
        }
    }

    private func alarmMenuItem(_ alarm: SchedAlarm) -> NSMenuItem {
        let item = NSMenuItem(title: Self.alarmMenuTitle(alarm), action: #selector(openAlarm(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = alarm.id.uuidString
        item.image = NSImage(systemSymbolName: alarm.repeatDaily ? "repeat" : "bell.fill", accessibilityDescription: nil)
        item.toolTip = alarm.note.isEmpty ? alarm.title : "\(alarm.title)\n\(alarm.note)"
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func menuItem(_ title: String, symbol: String? = nil, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    private func statusIcon() -> NSImage? {
        NSImage(systemSymbolName: "calendar", accessibilityDescription: "Sched Calendar")
    }

    private static func alarmMenuTitle(_ alarm: SchedAlarm) -> String {
        "\(SchedTimeFormat.string(from: alarm.fireAt))  \(compact(alarm.title, limit: 25))"
    }

    private static func compact(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(1, limit - 1))) + "…"
    }

    private func alarm(from sender: NSMenuItem) -> SchedAlarm? {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return nil }
        return ScheduleStore.shared.store.alarms.first { $0.id == id }
    }

    @objc private func openAlarm(_ sender: NSMenuItem) {
        guard let alarm = alarm(from: sender) else { return }
        MainWindowController.shared.showAlarm(alarm.id)
    }

    @objc private func openCalendarEvent(_ sender: NSMenuItem) {
        MainWindowController.shared.showCalendar(date: (sender.representedObject as? Date) ?? .now)
    }

    @objc private func requestCalendarAccess() {
        Task { @MainActor in
            _ = await CalendarService.shared.requestAccess()
            rebuildMenu()
        }
    }

    @objc private func newEvent() { MainWindowController.shared.createCalendarEvent(on: .now) }
    @objc private func newReminder() { MainWindowController.shared.createReminder(on: .now) }

    @objc private func openPlan() {
        MainWindowController.shared.showSection(.schedule)
        MainWindowController.shared.showWindow()
    }

    @objc private func openCalendar() { MainWindowController.shared.showCalendar(date: .now) }

    @objc private func openSettings() {
        MainWindowController.shared.showSection(.settings)
        MainWindowController.shared.showWindow()
    }

    @objc private func dismissAlerts() {
        AlarmAudioService.shared.stopAll()
        InterventionManager.shared.dismissAll()
    }

    @objc private func quit() {
        AlarmAudioService.shared.stopAll()
        InterventionManager.shared.dismissAll()
        NSApp.terminate(nil)
    }
}
