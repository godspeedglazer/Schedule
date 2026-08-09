import AppKit

@MainActor
final class ClockStatusController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusMenu = NSMenu()
    private var timer: Timer?
    private var timerInterval: TimeInterval?
    private var storeObserver: UUID?

    func install() {
        guard let button = statusItem.button else { return }
        button.image = statusIcon()
        button.image?.isTemplate = true
        button.toolTip = "Sched"

        statusMenu.delegate = self
        statusMenu.autoenablesItems = false
        statusItem.menu = statusMenu

        storeObserver = ScheduleStore.shared.observeChanges { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    private func refresh() {
        let preferences = ScheduleStore.shared.store
        configureRefreshTimer(for: preferences)

        guard let button = statusItem.button else { return }
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

        if let next = ScheduleStore.shared.nextAlarm() {
            let remaining = max(0, Int(next.fireAt.timeIntervalSinceNow))
            let minutes = (remaining + 59) / 60
            button.toolTip = "Next: \(next.title) at \(SchedTimeFormat.string(from: next.fireAt)) · \(minutes)m"
            if preferences.menuBarShowNextCountdown && remaining < 24 * 60 * 60 {
                components.append(Self.remainingText(remaining))
            }
        } else {
            button.toolTip = "No reminders scheduled"
        }

        let title = components.joined(separator: "  ·  ")
        button.title = title.isEmpty ? "" : " " + title
        button.imagePosition = title.isEmpty ? .imageOnly : .imageLeft
        button.font = preferences.menuBarShowSeconds
            ? NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : NSFont.menuBarFont(ofSize: 0)
        statusItem.length = title.isEmpty ? NSStatusItem.squareLength : NSStatusItem.variableLength
    }

    private func configureRefreshTimer(for preferences: KeenStore) {
        let interval: TimeInterval = preferences.menuBarShowSeconds ? 1 : 30
        guard timerInterval != interval || timer == nil else { return }

        timer?.invalidate()
        timerInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func refreshForSystemTimeChange() {
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()
        statusMenu.minimumWidth = 270

        statusMenu.addItem(menuItem("Open Sched", symbol: "calendar.badge.clock", action: #selector(openPlan)))

        let upcoming = Array(ScheduleStore.shared.enabledAlarms().prefix(3))
        if upcoming.isEmpty {
            let empty = NSMenuItem(title: "No upcoming reminders", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            statusMenu.addItem(empty)
        } else {
            statusMenu.addItem(.separator())
            for alarm in upcoming {
                let item = NSMenuItem(
                    title: Self.alarmMenuTitle(alarm),
                    action: #selector(openPlan),
                    keyEquivalent: ""
                )
                item.target = self
                item.image = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)
                item.toolTip = alarm.note.isEmpty ? alarm.title : "\(alarm.title)\n\(alarm.note)"
                statusMenu.addItem(item)
            }
        }

        statusMenu.addItem(.separator())
        let timerItem = NSMenuItem(title: "Start Timer", action: nil, keyEquivalent: "")
        timerItem.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
        let timerMenu = NSMenu()
        timerMenu.addItem(menuItem("5 minutes", action: #selector(start5)))
        timerMenu.addItem(menuItem("25 minutes", action: #selector(start25)))
        timerMenu.addItem(menuItem("50 minutes", action: #selector(start50)))
        timerItem.submenu = timerMenu
        statusMenu.addItem(timerItem)

        statusMenu.addItem(menuItem("Calendar", symbol: "calendar", action: #selector(openCalendar)))
        statusMenu.addItem(menuItem("Settings", symbol: "gearshape", action: #selector(openSettings)))

        let dismiss = menuItem("Dismiss Alerts", symbol: "bell.slash", action: #selector(dismissAlerts))
        dismiss.isEnabled = InterventionManager.shared.hasActive
        statusMenu.addItem(dismiss)

        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem("Quit Sched", action: #selector(quit)))
    }

    private func menuItem(_ title: String, symbol: String? = nil, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    private func statusIcon() -> NSImage? {
        NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Sched")
    }

    private static func alarmMenuTitle(_ alarm: KeenAlarm) -> String {
        let time = SchedTimeFormat.string(from: alarm.fireAt)
        return "\(time)  \(compact(alarm.title, limit: 18))"
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

    @objc private func openSettings() {
        MainWindowController.shared.showSection(.settings)
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
