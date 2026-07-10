import AppKit

@MainActor
final class ClockStatusController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenu = NSMenu()
    private var timer: Timer?
    private var storeObserver: UUID?

    func install() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Sched")
        button.image?.isTemplate = true
        statusMenu.delegate = self
        statusItem.menu = statusMenu
        storeObserver = ScheduleStore.shared.observeChanges { [weak self] in self?.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let timer { RunLoop.main.add(timer, forMode: .common) }
        refresh()
    }

    private func refresh() {
        let preferences = ScheduleStore.shared.store
        let button = statusItem.button
        button?.image = preferences.menuBarShowIcon
            ? NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Sched")
            : nil
        button?.image?.isTemplate = true

        var components: [String] = []
        if preferences.menuBarShowDate {
            let date = DateFormatter()
            date.setLocalizedDateFormatFromTemplate("E d")
            components.append(date.string(from: .now))
        }
        if preferences.menuBarShowTime {
            components.append(SchedTimeFormat.string(from: .now, includeSeconds: preferences.menuBarShowSeconds))
        }

        if let next = ScheduleStore.shared.nextAlarm() {
            let remaining = max(0, Int(next.fireAt.timeIntervalSinceNow))
            let minutes = (remaining + 59) / 60
            statusItem.button?.toolTip = "Next: \(next.title) at \(SchedTimeFormat.string(from: next.fireAt)) · \(minutes)m"
            if preferences.menuBarShowNextCountdown && remaining < 24 * 60 * 60 {
                components.append(Self.remainingText(remaining))
            }
        } else {
            statusItem.button?.toolTip = "No reminders scheduled"
        }
        let title = components.joined(separator: "  ·  ")
        button?.title = title.isEmpty ? "" : " " + title
        button?.imagePosition = title.isEmpty ? .imageOnly : .imageLeft
        button?.font = preferences.menuBarShowSeconds
            ? NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : NSFont.menuBarFont(ofSize: 0)
        statusItem.length = title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()
        statusMenu.minimumWidth = 280
        let calendarHost = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 164))
        let calendar = NSDatePicker()
        calendar.datePickerStyle = .clockAndCalendar
        calendar.datePickerElements = [.yearMonthDay]
        calendar.dateValue = .now
        calendar.isBordered = false
        calendar.translatesAutoresizingMaskIntoConstraints = false
        calendarHost.addSubview(calendar)
        NSLayoutConstraint.activate([
            calendar.centerXAnchor.constraint(equalTo: calendarHost.centerXAnchor),
            calendar.centerYAnchor.constraint(equalTo: calendarHost.centerYAnchor),
        ])
        let calendarItem = NSMenuItem()
        calendarItem.view = calendarHost
        statusMenu.addItem(calendarItem)
        statusMenu.addItem(.separator())

        if let next = ScheduleStore.shared.nextAlarm() {
            let remaining = max(0, Int(next.fireAt.timeIntervalSinceNow))
            let shortTitle = Self.compact(next.title, limit: 24)
            let nextItem = NSMenuItem(
                title: "Next · \(shortTitle) · \(Self.remainingText(remaining))",
                action: nil,
                keyEquivalent: ""
            )
            nextItem.image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)
            nextItem.isEnabled = false
            statusMenu.addItem(nextItem)
        } else {
            let empty = NSMenuItem(title: "No reminders scheduled", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            statusMenu.addItem(empty)
        }

        statusMenu.addItem(.separator())
        let timerItem = NSMenuItem(title: "Start Timer", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        timerMenu.addItem(menuItem("5 minutes", action: #selector(start5)))
        timerMenu.addItem(menuItem("25 minutes", action: #selector(start25)))
        timerMenu.addItem(menuItem("50 minutes", action: #selector(start50)))
        timerItem.submenu = timerMenu
        statusMenu.addItem(timerItem)
        statusMenu.addItem(menuItem("Open Plan", symbol: "list.bullet.rectangle", action: #selector(openPlan)))
        statusMenu.addItem(menuItem("Open Calendar", symbol: "calendar", action: #selector(openCalendar)))
        statusMenu.addItem(menuItem("Dismiss Alerts", symbol: "bell.slash", action: #selector(dismissAlerts)))
        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem("Quit Sched", action: #selector(quit)))
    }

    private func menuItem(_ title: String, symbol: String? = nil, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    private static func compact(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(1, limit - 1))) + "…"
    }

    private static func remainingText(_ seconds: Int) -> String {
        if seconds < 60 { return "now" }
        let minutes = (seconds + 59) / 60
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    @objc private func openPlan() {
        MainWindowController.shared.showSection(.schedule)
        MainWindowController.shared.showWindow()
    }

    @objc private func openCalendar() {
        MainWindowController.shared.showSection(.calendar)
        MainWindowController.shared.showWindow()
    }

    @objc private func start5() { startTimer(minutes: 5) }
    @objc private func start25() { startTimer(minutes: 25) }
    @objc private func start50() { startTimer(minutes: 50) }

    private func startTimer(minutes: Int) {
        _ = Scheduler.shared.scheduleIn(
            title: "Focus",
            note: "Timer complete. Take a breath before the next thing.",
            minutes: minutes,
            level: .gentle
        )
    }

    @objc private func dismissAlerts() {
        InterventionManager.shared.dismissAll()
    }

    @objc private func quit() {
        InterventionManager.shared.dismissAll()
        NSApp.terminate(nil)
    }
}
