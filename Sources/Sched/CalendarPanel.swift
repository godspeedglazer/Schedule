import AppKit
import EventKit

@MainActor
final class CalendarPanelController: NSViewController {
    private let monthCalendar = SchedMonthCalendarView()
    private let selectedDateLabel = NSTextField(labelWithString: "")
    private let agendaStack = NSStackView()
    private let accessButton = SchedPrimaryButton("Enable Calendar Access", action: #selector(requestCalendarAccess), target: nil)
    private var storeObserver: UUID?
    private var calendarObserver: UUID?
    private var activeObserver: NSObjectProtocol?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear

        let title = NSTextField(labelWithString: "Calendar")
        title.font = SchedDesign.display(28)
        SchedDesign.label(title)
        let subtitle = NSTextField(labelWithString: "Your reminders and Mac calendar, in one place.")
        subtitle.font = SchedDesign.body(14)
        SchedDesign.label(subtitle, color: SchedDesign.inkMuted)

        let calendarGlass = SchedGlassSurface(cornerRadius: 20, tint: NSColor.white.withAlphaComponent(0.14))
        monthCalendar.onSelection = { [weak self] _ in self?.reloadAgenda() }
        monthCalendar.translatesAutoresizingMaskIntoConstraints = false
        calendarGlass.innerContentView.addSubview(monthCalendar)
        NSLayoutConstraint.activate([
            monthCalendar.leadingAnchor.constraint(equalTo: calendarGlass.innerContentView.leadingAnchor, constant: 16),
            monthCalendar.trailingAnchor.constraint(equalTo: calendarGlass.innerContentView.trailingAnchor, constant: -16),
            monthCalendar.topAnchor.constraint(equalTo: calendarGlass.innerContentView.topAnchor, constant: 16),
            monthCalendar.heightAnchor.constraint(equalToConstant: 272),
        ])

        let today = SchedGhostButton("Today", action: #selector(goToToday), target: self)
        let addEvent = SchedPrimaryButton("＋ Event", action: #selector(addEvent), target: self)
        let addReminder = SchedGhostButton("＋ Reminder", action: #selector(addReminder), target: self)
        let calendarActions = NSStackView(views: [today, addEvent, addReminder])
        calendarActions.orientation = .horizontal
        calendarActions.spacing = 7
        calendarActions.translatesAutoresizingMaskIntoConstraints = false
        calendarGlass.innerContentView.addSubview(calendarActions)
        NSLayoutConstraint.activate([
            calendarActions.leadingAnchor.constraint(equalTo: monthCalendar.leadingAnchor),
            calendarActions.bottomAnchor.constraint(equalTo: calendarGlass.innerContentView.bottomAnchor, constant: -16),
            calendarActions.topAnchor.constraint(equalTo: monthCalendar.bottomAnchor, constant: 14),
        ])

        let agendaGlass = SchedGlassSurface(cornerRadius: 20, tint: NSColor.white.withAlphaComponent(0.14))
        selectedDateLabel.font = SchedDesign.title(18)
        selectedDateLabel.lineBreakMode = .byTruncatingTail
        SchedDesign.label(selectedDateLabel)
        agendaStack.orientation = .vertical
        agendaStack.alignment = .leading
        agendaStack.spacing = 8
        agendaStack.translatesAutoresizingMaskIntoConstraints = false

        let document = SchedFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(agendaStack)
        NSLayoutConstraint.activate([
            agendaStack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            agendaStack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            agendaStack.topAnchor.constraint(equalTo: document.topAnchor),
            agendaStack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -8),
        ])
        let scroll = NSScrollView()
        schedConfigureScroll(scroll)
        scroll.documentView = document
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.widthAnchor.constraint(equalTo: clip.widthAnchor),
        ])

        let agendaHost = agendaGlass.innerContentView
        [selectedDateLabel, scroll].forEach { agendaHost.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            selectedDateLabel.leadingAnchor.constraint(equalTo: agendaHost.leadingAnchor, constant: 18),
            selectedDateLabel.trailingAnchor.constraint(equalTo: agendaHost.trailingAnchor, constant: -18),
            selectedDateLabel.topAnchor.constraint(equalTo: agendaHost.topAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: selectedDateLabel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: selectedDateLabel.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: selectedDateLabel.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: agendaHost.bottomAnchor, constant: -18),
        ])

        [title, subtitle, calendarGlass, agendaGlass].forEach { view.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            calendarGlass.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 16),
            calendarGlass.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            calendarGlass.heightAnchor.constraint(equalToConstant: 360),
            calendarGlass.widthAnchor.constraint(equalToConstant: 292),
            agendaGlass.topAnchor.constraint(equalTo: calendarGlass.topAnchor),
            agendaGlass.leadingAnchor.constraint(equalTo: calendarGlass.trailingAnchor, constant: 14),
            agendaGlass.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            agendaGlass.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        accessButton.target = self
        reloadAgenda()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if storeObserver == nil {
            storeObserver = ScheduleStore.shared.observeChanges { [weak self] in self?.reloadAgenda() }
        }
        if calendarObserver == nil {
            calendarObserver = CalendarService.shared.observeChanges { [weak self] in self?.reloadAgenda() }
        }
        if activeObserver == nil {
            activeObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.reloadAgenda() }
            }
        }
        reloadAgenda()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let storeObserver {
            ScheduleStore.shared.removeObserver(storeObserver)
            self.storeObserver = nil
        }
        if let calendarObserver {
            CalendarService.shared.removeObserver(calendarObserver)
            self.calendarObserver = nil
        }
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
            self.activeObserver = nil
        }
    }

    func select(date: Date) {
        monthCalendar.select(date: date)
        if isViewLoaded { reloadAgenda() }
    }

    func createEvent(on date: Date) {
        guard let window = view.window else { return }
        CalendarEventEditorController.present(from: window, seed: .newEvent(on: date)) { [weak self] event in
            self?.monthCalendar.select(date: event.startDate)
            self?.reloadAgenda()
        }
    }

    func createReminder(on date: Date) {
        let calendar = Calendar.autoupdatingCurrent
        let fireAt: Date
        if calendar.isDateInToday(date) {
            fireAt = Date().addingTimeInterval(30 * 60)
        } else {
            fireAt = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
        }
        let alarm = SchedAlarm(
            title: "New reminder",
            fireAt: fireAt,
            level: ScheduleStore.shared.store.defaultLevel
        )
        ScheduleStore.shared.upsert(alarm)
        MainWindowController.shared.showAlarm(alarm.id)
    }

    @objc private func goToToday() {
        select(date: .now)
    }

    @objc private func addEvent() {
        createEvent(on: monthCalendar.selectedDate)
    }

    @objc private func addReminder() {
        createReminder(on: monthCalendar.selectedDate)
    }

    @objc private func requestCalendarAccess() {
        Task { [weak self] in
            _ = await CalendarService.shared.requestAccess()
            self?.reloadAgenda()
        }
    }

    private func reloadAgenda() {
        guard isViewLoaded else { return }
        let date = monthCalendar.selectedDate
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        selectedDateLabel.stringValue = formatter.string(from: date)
        agendaStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let reminderEntries = ScheduleStore.shared.store.alarms.compactMap { alarm -> AgendaEntry? in
            guard alarm.enabled, !alarm.isTimer, let occurrence = reminderOccurrence(for: alarm, on: date) else { return nil }
            return AgendaEntry(
                sortDate: occurrence,
                allDay: false,
                time: SchedTimeFormat.string(from: occurrence),
                title: alarm.title,
                detail: alarm.note.isEmpty ? (alarm.repeatDaily ? "Daily Sched reminder" : "Sched reminder") : alarm.note,
                color: SchedDesign.levelColor(alarm.level),
                symbol: "bell.fill",
                alarmID: alarm.id,
                eventIdentifier: nil
            )
        }

        let eventEntries = CalendarService.shared.events(on: date).map { event in
            let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detail = location.isEmpty ? event.calendar.title : "\(event.calendar.title) · \(location)"
            return AgendaEntry(
                sortDate: event.startDate,
                allDay: event.isAllDay,
                time: event.isAllDay ? "All day" : SchedTimeFormat.string(from: event.startDate),
                title: event.title ?? "Untitled event",
                detail: detail,
                color: NSColor(cgColor: event.calendar.cgColor) ?? SchedDesign.accent,
                symbol: "calendar",
                alarmID: nil,
                eventIdentifier: event.eventIdentifier
            )
        }

        if !CalendarService.shared.hasAccess {
            agendaStack.addArrangedSubview(helper("Connect Calendar to see events here and create new ones from Sched."))
            agendaStack.addArrangedSubview(accessButton)
        }

        let entries = (reminderEntries + eventEntries).sorted { lhs, rhs in
            if lhs.allDay != rhs.allDay { return lhs.allDay }
            if lhs.sortDate != rhs.sortDate { return lhs.sortDate < rhs.sortDate }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }

        for entry in entries {
            addAgendaRow(agendaRow(entry))
        }

        if entries.isEmpty && CalendarService.shared.hasAccess {
            agendaStack.addArrangedSubview(helper("Nothing scheduled for this day. Use + Event or + Reminder to add something."))
        }
    }

    private func reminderOccurrence(for alarm: SchedAlarm, on date: Date) -> Date? {
        let calendar = Calendar.autoupdatingCurrent
        if !alarm.repeatDaily {
            return calendar.isDate(alarm.fireAt, inSameDayAs: date) ? alarm.fireAt : nil
        }

        let selectedDay = calendar.startOfDay(for: date)
        let firstScheduledDay = calendar.startOfDay(for: alarm.fireAt)
        guard selectedDay >= firstScheduledDay else { return nil }

        let time = calendar.dateComponents([.hour, .minute, .second], from: alarm.fireAt)
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = time.hour
        components.minute = time.minute
        components.second = time.second
        return calendar.date(from: components)
    }

    private struct AgendaEntry {
        let sortDate: Date
        let allDay: Bool
        let time: String
        let title: String
        let detail: String
        let color: NSColor
        let symbol: String
        let alarmID: UUID?
        let eventIdentifier: String?
    }

    private func addAgendaRow(_ row: NSView) {
        agendaStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: agendaStack.widthAnchor).isActive = true
    }

    private func agendaRow(_ entry: AgendaEntry) -> NSView {
        let row = SchedGlassSurface(cornerRadius: 12, tint: entry.color.withAlphaComponent(0.10), interactive: false)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 64).isActive = true

        let icon = NSImageView(image: NSImage(systemSymbolName: entry.symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = entry.color
        let timeLabel = NSTextField(labelWithString: entry.time)
        timeLabel.font = SchedDesign.mono(11)
        timeLabel.lineBreakMode = .byTruncatingTail
        SchedDesign.label(timeLabel, color: SchedDesign.inkMuted)

        let titleLabel = SchedFadingLabel(entry.title)
        titleLabel.font = SchedDesign.title(14)
        titleLabel.toolTip = entry.title
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        SchedDesign.label(titleLabel)

        let detailLabel = NSTextField(wrappingLabelWithString: entry.detail)
        detailLabel.font = SchedDesign.body(11)
        detailLabel.maximumNumberOfLines = 3
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.toolTip = entry.detail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        SchedDesign.label(detailLabel, color: SchedDesign.inkMuted)

        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let content = NSStackView(views: [icon, timeLabel, text])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.spacing = 10
        content.translatesAutoresizingMaskIntoConstraints = false
        row.innerContentView.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: row.innerContentView.leadingAnchor, constant: 12),
            content.trailingAnchor.constraint(equalTo: row.innerContentView.trailingAnchor, constant: -12),
            content.topAnchor.constraint(equalTo: row.innerContentView.topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: row.innerContentView.bottomAnchor, constant: -10),
            icon.widthAnchor.constraint(equalToConstant: 16),
            timeLabel.widthAnchor.constraint(equalToConstant: 62),
        ])

        if let alarmID = entry.alarmID {
            let menu = NSMenu()
            menu.addItem(agendaAction("Edit Reminder", symbol: "slider.horizontal.3", represented: alarmID.uuidString, action: #selector(editAgendaReminder(_:))))
            menu.addItem(agendaAction("Add to Calendar…", symbol: "calendar.badge.plus", represented: alarmID.uuidString, action: #selector(pushReminderToCalendar(_:))))
            menu.addItem(agendaAction("Snooze 5 Minutes", symbol: "clock.arrow.circlepath", represented: alarmID.uuidString, action: #selector(snoozeAgendaReminder(_:))))
            menu.addItem(agendaAction("Disable", symbol: "pause.circle", represented: alarmID.uuidString, action: #selector(disableAgendaReminder(_:))))
            menu.addItem(.separator())
            menu.addItem(agendaAction("Delete", symbol: "trash", represented: alarmID.uuidString, action: #selector(deleteAgendaReminder(_:))))
            row.menu = menu
        } else if let identifier = entry.eventIdentifier {
            let menu = NSMenu()
            menu.addItem(agendaAction("Create Sched Reminder…", symbol: "bell.badge.plus", represented: identifier, action: #selector(createReminderFromEvent(_:))))
            row.menu = menu
        }
        return row
    }

    private func agendaAction(_ title: String, symbol: String, represented: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = represented
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    private func agendaAlarm(from sender: NSMenuItem) -> SchedAlarm? {
        guard let raw = sender.representedObject as? String, let id = UUID(uuidString: raw) else { return nil }
        return ScheduleStore.shared.store.alarms.first { $0.id == id }
    }

    @objc private func editAgendaReminder(_ sender: NSMenuItem) {
        guard let alarm = agendaAlarm(from: sender) else { return }
        MainWindowController.shared.showAlarm(alarm.id)
    }

    @objc private func pushReminderToCalendar(_ sender: NSMenuItem) {
        guard let alarm = agendaAlarm(from: sender), let window = view.window else { return }
        CalendarEventEditorController.present(from: window, seed: .reminder(alarm)) { event in
            var updated = alarm
            updated.calendarEventIdentifier = event.eventIdentifier
            ScheduleStore.shared.upsert(updated)
        }
    }

    @objc private func createReminderFromEvent(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              let event = CalendarService.shared.event(identifier: identifier) else { return }
        let fireAt: Date
        if event.isAllDay {
            fireAt = Calendar.autoupdatingCurrent.date(bySettingHour: 9, minute: 0, second: 0, of: event.startDate) ?? event.startDate
        } else {
            fireAt = event.startDate
        }
        let noteParts = [event.location, event.notes]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let alarm = SchedAlarm(
            title: SchedTextLimits.clean(event.title ?? "Calendar event", limit: SchedTextLimits.title),
            note: SchedTextLimits.clean(noteParts.joined(separator: "\n"), limit: SchedTextLimits.note),
            fireAt: fireAt,
            level: ScheduleStore.shared.store.defaultLevel,
            calendarEventIdentifier: identifier
        )
        ScheduleStore.shared.upsert(alarm)
        MainWindowController.shared.showAlarm(alarm.id)
    }

    @objc private func snoozeAgendaReminder(_ sender: NSMenuItem) {
        guard var alarm = agendaAlarm(from: sender) else { return }
        if alarm.repeatDaily {
            alarm.id = UUID()
            alarm.repeatDaily = false
            alarm.calendarEventIdentifier = nil
        }
        alarm.fireAt = Date().addingTimeInterval(5 * 60)
        alarm.enabled = true
        alarm.pausedRemainingSeconds = nil
        ScheduleStore.shared.upsert(alarm)
    }

    @objc private func disableAgendaReminder(_ sender: NSMenuItem) {
        guard var alarm = agendaAlarm(from: sender) else { return }
        alarm.enabled = false
        AlarmAudioService.shared.stop(alarmID: alarm.id)
        InterventionManager.shared.dismiss(alarmID: alarm.id)
        ScheduleStore.shared.upsert(alarm)
    }

    @objc private func deleteAgendaReminder(_ sender: NSMenuItem) {
        guard let alarm = agendaAlarm(from: sender) else { return }
        AlarmAudioService.shared.stop(alarmID: alarm.id)
        InterventionManager.shared.dismiss(alarmID: alarm.id)
        ScheduleStore.shared.remove(id: alarm.id)
    }

    private func helper(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = SchedDesign.body(12)
        label.maximumNumberOfLines = 0
        SchedDesign.label(label, color: SchedDesign.inkMuted)
        return label
    }
}

/// A native AppKit month grid sized for Sched's calendar panel. `NSDatePicker`'s
/// calendar style has a fixed intrinsic size, which caused the tiny floating
/// control that this view replaces.
@MainActor
private final class SchedMonthCalendarView: NSView {
    var onSelection: ((Date) -> Void)?
    private(set) var selectedDate = Date()

    private let monthLabel = NSTextField(labelWithString: "")
    private let weekdayRow = NSStackView()
    private let weeks = NSStackView()
    private var visibleMonth = Calendar.autoupdatingCurrent.dateInterval(of: .month, for: .now)?.start ?? .now
    private var dayButtons: [SchedDayButton] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false

        monthLabel.font = SchedDesign.title(17)
        SchedDesign.label(monthLabel)
        let previous = navigationButton(symbol: "chevron.left", action: #selector(previousMonth))
        let next = navigationButton(symbol: "chevron.right", action: #selector(nextMonth))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [monthLabel, spacer, previous, next])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 6

        weekdayRow.orientation = .horizontal
        weekdayRow.distribution = .fillEqually
        weekdayRow.spacing = 4
        weeks.orientation = .vertical
        weeks.distribution = .fillEqually
        weeks.spacing = 4

        for _ in 0..<6 {
            let row = NSStackView()
            row.orientation = .horizontal
            row.distribution = .fillEqually
            row.spacing = 4
            row.translatesAutoresizingMaskIntoConstraints = false
            for _ in 0..<7 {
                let button = SchedDayButton()
                button.target = self
                button.action = #selector(daySelected(_:))
                button.heightAnchor.constraint(equalToConstant: 30).isActive = true
                dayButtons.append(button)
                row.addArrangedSubview(button)
            }
            weeks.addArrangedSubview(row)
            // A vertical NSStackView does not automatically make its arranged rows
            // as wide as itself. Without this, the day grid shrinks to the buttons'
            // intrinsic widths while the weekday header spans the full panel.
            row.widthAnchor.constraint(equalTo: weeks.widthAnchor).isActive = true
        }

        let stack = NSStackView(views: [header, weekdayRow, weeks])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor),
            weekdayRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            weeks.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        reload()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func select(date: Date) {
        selectedDate = date
        visibleMonth = Calendar.autoupdatingCurrent.dateInterval(of: .month, for: date)?.start ?? date
        reload()
    }

    private func navigationButton(symbol: String, action: Selector) -> NSButton {
        let button = NSButton(
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(),
            target: self,
            action: action
        )
        button.isBordered = false
        button.contentTintColor = SchedDesign.inkMuted
        button.widthAnchor.constraint(equalToConstant: 28).isActive = true
        button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return button
    }

    @objc private func previousMonth() { moveMonth(-1) }
    @objc private func nextMonth() { moveMonth(1) }

    private func moveMonth(_ amount: Int) {
        visibleMonth = Calendar.autoupdatingCurrent.date(byAdding: .month, value: amount, to: visibleMonth) ?? visibleMonth
        reload()
    }

    @objc private func daySelected(_ sender: SchedDayButton) {
        guard let date = sender.date else { return }
        selectedDate = date
        if !Calendar.autoupdatingCurrent.isDate(date, equalTo: visibleMonth, toGranularity: .month) {
            visibleMonth = Calendar.autoupdatingCurrent.dateInterval(of: .month, for: date)?.start ?? date
        }
        reload()
        onSelection?(date)
    }

    private func reload() {
        let calendar = Calendar.autoupdatingCurrent
        let monthFormatter = DateFormatter()
        monthFormatter.locale = .autoupdatingCurrent
        monthFormatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        monthLabel.stringValue = monthFormatter.string(from: visibleMonth)

        weekdayRow.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(0, calendar.firstWeekday - 1)
        for index in 0..<7 {
            let label = NSTextField(labelWithString: symbols[(index + offset) % 7])
            label.alignment = .center
            label.font = SchedDesign.caption(10)
            SchedDesign.label(label, color: SchedDesign.inkMuted)
            weekdayRow.addArrangedSubview(label)
        }

        let weekday = calendar.component(.weekday, from: visibleMonth)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let firstVisible = calendar.date(byAdding: .day, value: -leading, to: visibleMonth) ?? visibleMonth
        let accessibilityFormatter = DateFormatter()
        accessibilityFormatter.dateStyle = .full
        accessibilityFormatter.timeStyle = .none
        for (index, button) in dayButtons.enumerated() {
            let date = calendar.date(byAdding: .day, value: index, to: firstVisible) ?? firstVisible
            button.date = date
            button.title = String(calendar.component(.day, from: date))
            button.isInVisibleMonth = calendar.isDate(date, equalTo: visibleMonth, toGranularity: .month)
            button.isSelectedDate = calendar.isDate(date, inSameDayAs: selectedDate)
            button.isToday = calendar.isDateInToday(date)
            button.setAccessibilityLabel(accessibilityFormatter.string(from: date))
            button.refreshStyle()
        }
    }
}

@MainActor
private final class SchedDayButton: NSButton {
    var date: Date?
    var isInVisibleMonth = true
    var isSelectedDate = false
    var isToday = false

    init() {
        super.init(frame: .zero)
        isBordered = false
        focusRingType = .none
        wantsLayer = true
        layer?.cornerRadius = 8
        font = SchedDesign.body(12)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func refreshStyle() {
        layer?.backgroundColor = isSelectedDate ? SchedDesign.accent.cgColor : NSColor.clear.cgColor
        layer?.borderWidth = isToday && !isSelectedDate ? 1.5 : 0
        layer?.borderColor = SchedDesign.accent.cgColor
        contentTintColor = isSelectedDate ? .white : (isInVisibleMonth ? SchedDesign.ink : SchedDesign.inkFaint)
        alphaValue = isInVisibleMonth ? 1 : 0.55
    }
}
