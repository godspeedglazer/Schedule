import AppKit

@MainActor
final class TimerStatusController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let statusMenu = NSMenu()
    private var refreshTimer: Timer?
    private var refreshInterval: TimeInterval?
    private var storeObserver: UUID?
    private var timerObserver: UUID?

    func install() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = "Sched.TimerStatusItem"
        statusItem = item

        statusMenu.delegate = self
        statusMenu.autoenablesItems = false
        item.menu = statusMenu

        storeObserver = ScheduleStore.shared.observeChanges { [weak self] in self?.refresh() }
        timerObserver = TimerService.shared.observeChanges { [weak self] in self?.refresh() }
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
        let snapshot = TimerService.shared.snapshot()
        let shouldShow = preferences.menuBarTimerEnabled
            && !(preferences.menuBarTimerHideWhenIdle && snapshot == nil)
        item.isVisible = shouldShow
        guard shouldShow else {
            stopRefreshTimer()
            return
        }

        if let snapshot {
            button.image = NSImage(
                systemSymbolName: snapshot.isPaused ? "pause.circle.fill" : "timer",
                accessibilityDescription: "Sched timer"
            )
            button.image?.isTemplate = true
            button.title = " " + snapshot.formattedRemaining
            button.imagePosition = .imageLeft
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .medium)
            button.toolTip = snapshot.isPaused
                ? "\(snapshot.title) · paused"
                : "\(snapshot.title) · \(snapshot.formattedRemaining) remaining"
            item.length = NSStatusItem.variableLength
            configureRefreshTimer(active: !snapshot.isPaused)
        } else {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Sched timer")
            button.image?.isTemplate = true
            button.title = ""
            button.imagePosition = .imageOnly
            button.font = NSFont.menuBarFont(ofSize: 0)
            button.toolTip = "Sched Timer"
            item.length = NSStatusItem.squareLength
            stopRefreshTimer()
        }
    }

    private func configureRefreshTimer(active: Bool) {
        guard active else {
            stopRefreshTimer()
            return
        }
        let interval: TimeInterval = 1
        guard refreshTimer == nil || refreshInterval != interval else { return }
        refreshTimer?.invalidate()
        refreshInterval = interval
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        refreshInterval = nil
    }

    private func rebuildMenu() {
        statusMenu.removeAllItems()
        statusMenu.minimumWidth = 250

        if let snapshot = TimerService.shared.snapshot() {
            let title = NSMenuItem(title: Self.compact(snapshot.title, limit: 28), action: nil, keyEquivalent: "")
            title.isEnabled = false
            title.image = NSImage(systemSymbolName: "timer", accessibilityDescription: nil)
            statusMenu.addItem(title)

            let remaining = NSMenuItem(
                title: snapshot.isPaused ? "\(snapshot.formattedRemaining) paused" : "\(snapshot.formattedRemaining) remaining",
                action: nil,
                keyEquivalent: ""
            )
            remaining.isEnabled = false
            statusMenu.addItem(remaining)
            statusMenu.addItem(.separator())

            statusMenu.addItem(menuItem(
                snapshot.isPaused ? "Resume" : "Pause",
                symbol: snapshot.isPaused ? "play.fill" : "pause.fill",
                action: #selector(pauseOrResume)
            ))
            statusMenu.addItem(menuItem("Add 5 Minutes", symbol: "plus", action: #selector(addFive)))
            statusMenu.addItem(menuItem("Show Floating Timer", symbol: "macwindow.on.rectangle", action: #selector(showFloating)))
            statusMenu.addItem(menuItem("Finish", symbol: "checkmark", action: #selector(finish)))
            statusMenu.addItem(menuItem("Cancel Timer", symbol: "xmark", action: #selector(cancel)))
        } else {
            let quickStart = NSMenuItem()
            quickStart.view = TimerQuickStartMenuView { [weak self] minutes in
                _ = TimerService.shared.start(minutes: minutes)
                self?.statusMenu.cancelTracking()
                self?.refresh()
            }
            statusMenu.addItem(quickStart)

            let presetsRoot = NSMenuItem(title: "Saved durations", action: nil, keyEquivalent: "")
            presetsRoot.image = NSImage(systemSymbolName: "clock", accessibilityDescription: nil)
            let presets = NSMenu(title: "Saved durations")
            for minutes in [5, 15, 25, 50, 90] {
                let item = NSMenuItem(title: "\(minutes) minutes", action: #selector(startPreset(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = minutes
                presets.addItem(item)
            }
            presetsRoot.submenu = presets
            statusMenu.addItem(presetsRoot)
        }

        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem("Open Timer", symbol: "timer", action: #selector(openTimer)))
        statusMenu.addItem(menuItem("Preferences", symbol: "gearshape", action: #selector(openPreferences)))
        statusMenu.addItem(.separator())
        statusMenu.addItem(menuItem("Quit Sched", action: #selector(quit)))
    }

    private func menuItem(_ title: String, symbol: String? = nil, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }

    @objc private func startPreset(_ sender: NSMenuItem) {
        let minutes = sender.representedObject as? Int ?? 25
        _ = TimerService.shared.start(minutes: minutes)
        statusMenu.cancelTracking()
    }

    @objc private func pauseOrResume() { TimerService.shared.pauseOrResume() }
    @objc private func addFive() { TimerService.shared.add(minutes: 5) }
    @objc private func finish() { TimerService.shared.finish() }
    @objc private func cancel() { TimerService.shared.cancel() }
    @objc private func showFloating() { FloatingTimerController.shared.show() }

    @objc private func openTimer() {
        MainWindowController.shared.showSection(.timer)
        MainWindowController.shared.showWindow()
    }

    @objc private func openPreferences() {
        MainWindowController.shared.showSection(.settings)
        MainWindowController.shared.showWindow()
    }

    @objc private func quit() {
        AlarmAudioService.shared.stopAll()
        InterventionManager.shared.dismissAll()
        NSApp.terminate(nil)
    }

    private static func compact(_ value: String, limit: Int) -> String {
        guard value.count > limit else { return value }
        return String(value.prefix(max(1, limit - 1))) + "…"
    }
}
