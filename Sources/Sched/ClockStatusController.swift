import AppKit
import EventKit

@MainActor
final class ClockStatusController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var timer: Timer?
    private var timerInterval: TimeInterval?
    private var storeObserver: UUID?

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Sched.ClockStatusItem"
        statusItem = item

        statusMenu.delegate = self
        statusMenu.autoenablesItems = false
        item.menu = statusMenu

        storeObserver = ScheduleStore.shared.observeChanges { [weak self] in self?.refresh() }
        refresh()
    }

    func refreshForSystemTimeChange() {
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func refresh() {
        guard let item = statusItem, let button = item.button else { return }
        let preferences = ScheduleStore.shared.store
        item.isVisible = preferences.menuBarClockEnabled
        configureRefreshTimer(for: preferences)
        guard preferences.menuBarClockEnabled else { return }

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
        let interval: TimeInterval = preferences.menuBarShowSeconds ? 1 : 30
        guard timerInterval != interval || timer == nil else { return }
        timer?.invalidate()
        timerInterval = interval
        let refreshTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer = refreshTimer
        RunLoop.main.add(refreshTimer, forMode: .common)
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()
        statusMenu.minimumWidth = 292

        let calendarItem = NSMenuItem()
        calendarItem.view = ClockCalendarMenuView()
        statusMenu.addItem(calendarItem)

        let todayFormatter = DateFormatter()
        todayFormatter.locale = .autoupdatingCurrent
        todayFormatter.dateStyle = .full
        todayFormatter.timeStyle = .none
        let today = NSMenuItem(title: todayFormatter.string(from: .now), action: nil, keyEquivalent: "")
        today.isEnabled = false
        statusMenu.addItem(today)

        statusMenu.addItem(.separator())
        addTodayAgenda(to: statusMenu)

        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem("Open Calendar", symbol: "calendar", action: #selector(openCalendar)))
        statusMenu.addItem(menuItem("Open Plan", symbol: "list.bullet.rectangle", action: #selector(openPlan)))
        statusMenu.addItem(menuItem("Preferences", symbol: "gearshape", action: #selector(openSettings)))

        let dismiss = menuItem("Dismiss Alerts", symbol: "bell.slash", action: #selector(dismissAlerts))
        dismiss.isEnabled = InterventionManager.shared.hasActive
        statusMenu.addItem(dismiss)

        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem("Quit Sched", action: #selector(quit)))
    }

    private struct TodayAgendaEntry {
        enum Kind {
            case alarm(SchedAlarm)
            case event(EKEvent)
        }

        let date: Date
        let isAllDay: Bool
        let kind: Kind
    }

    private func addTodayAgenda(to menu: NSMenu) {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let alarms = ScheduleStore.shared.enabledAlarms()
            .filter { !$0.isTimer && calendar.isDate($0.fireAt, inSameDayAs: now) }
            .map { TodayAgendaEntry(date: $0.fireAt, isAllDay: false, kind: .alarm($0)) }

        var entries = alarms
        if CalendarService.shared.hasAccess {
            entries += CalendarService.shared.events(on: now).map { event in
                TodayAgendaEntry(date: event.startDate, isAllDay: event.isAllDay, kind: .event(event))
            }
        }
        entries.sort { left, right in
            if left.isAllDay != right.isAllDay { return left.isAllDay && !right.isAllDay }
            return left.date < right.date
        }

        if entries.isEmpty {
            if CalendarService.shared.hasAccess {
                let empty = NSMenuItem(title: "Nothing scheduled today", action: nil, keyEquivalent: "")
                empty.isEnabled = false
                menu.addItem(empty)
            } else {
                let access = menuItem("Enable Calendar Access…", symbol: "calendar.badge.plus", action: #selector(requestCalendarAccess))
                menu.addItem(access)

                if let next = ScheduleStore.shared.enabledAlarms().first(where: { !$0.isTimer }) {
                    let heading = NSMenuItem(title: "Next Reminder", action: nil, keyEquivalent: "")
                    heading.isEnabled = false
                    menu.addItem(heading)
                    menu.addItem(alarmMenuItem(next))
                }
            }
            return
        }

        for entry in entries.prefix(6) {
            switch entry.kind {
            case .alarm(let alarm):
                menu.addItem(alarmMenuItem(alarm))
            case .event(let event):
                let time = event.isAllDay ? "All day" : SchedTimeFormat.string(from: event.startDate)
                let title = "\(time)  \(Self.compact(event.title ?? "Calendar event", limit: 24))"
                let item = NSMenuItem(title: title, action: #selector(openCalendar), keyEquivalent: "")
                item.target = self
                item.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: nil)
                item.toolTip = event.calendar.title
                menu.addItem(item)
            }
        }

        if entries.count > 6 {
            let more = NSMenuItem(title: "+\(entries.count - 6) more today", action: #selector(openCalendar), keyEquivalent: "")
            more.target = self
            menu.addItem(more)
        }
    }

    private func alarmMenuItem(_ alarm: SchedAlarm) -> NSMenuItem {
        let item = NSMenuItem(title: Self.alarmMenuTitle(alarm), action: #selector(openAlarm(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = alarm.id.uuidString
        item.image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)
        item.toolTip = alarm.note.isEmpty ? alarm.title : "\(alarm.title)\n\(alarm.note)"

        let submenu = NSMenu()
        submenu.addItem(alarmActionItem("Open in Plan", symbol: "arrow.up.forward.app", alarm: alarm, action: #selector(openAlarm(_:))))
        submenu.addItem(alarmActionItem("Snooze 5 Minutes", symbol: "clock.arrow.circlepath", alarm: alarm, action: #selector(snoozeAlarm(_:))))
        submenu.addItem(alarmActionItem("Disable", symbol: "pause.circle", alarm: alarm, action: #selector(disableAlarm(_:))))
        submenu.addItem(.separator())
        submenu.addItem(alarmActionItem("Delete", symbol: "trash", alarm: alarm, action: #selector(deleteAlarm(_:))))
        item.submenu = submenu
        return item
    }

    private func alarmActionItem(_ title: String, symbol: String, alarm: SchedAlarm, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = alarm.id.uuidString
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
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
        let time = SchedTimeFormat.string(from: alarm.fireAt)
        return "\(time)  \(compact(alarm.title, limit: 24))"
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
        guard let alarm = alarm(from: sender) else {
            openPlan()
            return
        }
        MainWindowController.shared.showAlarm(alarm.id)
    }

    @objc private func snoozeAlarm(_ sender: NSMenuItem) {
        guard var alarm = alarm(from: sender) else { return }
        if alarm.repeatDaily {
            alarm.id = UUID()
            alarm.repeatDaily = false
        }
        alarm.fireAt = Date().addingTimeInterval(5 * 60)
        alarm.enabled = true
        alarm.pausedRemainingSeconds = nil
        ScheduleStore.shared.upsert(alarm)
    }

    @objc private func disableAlarm(_ sender: NSMenuItem) {
        guard var alarm = alarm(from: sender) else { return }
        alarm.enabled = false
        AlarmAudioService.shared.stop(alarmID: alarm.id)
        InterventionManager.shared.dismiss(alarmID: alarm.id)
        ScheduleStore.shared.upsert(alarm)
    }

    @objc private func deleteAlarm(_ sender: NSMenuItem) {
        guard let alarm = alarm(from: sender) else { return }
        AlarmAudioService.shared.stop(alarmID: alarm.id)
        InterventionManager.shared.dismiss(alarmID: alarm.id)
        ScheduleStore.shared.remove(id: alarm.id)
    }

    @objc private func requestCalendarAccess() {
        Task { @MainActor in
            _ = await CalendarService.shared.requestAccess()
            rebuildMenu()
        }
    }

    @objc private func openPlan() {
        MainWindowController.shared.showSection(.schedule)
        MainWindowController.shared.showWindow()
    }

    @objc private func openCalendar() {
        MainWindowController.shared.showSection(.calendar)
        MainWindowController.shared.showWindow()
    }

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
