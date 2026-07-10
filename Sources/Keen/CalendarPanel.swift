import AppKit
import EventKit

@MainActor
final class CalendarPanelController: NSViewController {
    private let monthCalendar = SchedMonthCalendarView()
    private let selectedDateLabel = NSTextField(labelWithString: "")
    private let agendaStack = NSStackView()
    private let accessButton = KeenPrimaryButton("Show Calendar Events", action: #selector(requestCalendarAccess), target: nil)
    private var storeObserver: UUID?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear

        let title = NSTextField(labelWithString: "Calendar")
        title.font = KeenDesign.display(28)
        KeenDesign.label(title)
        let subtitle = NSTextField(labelWithString: "Your reminders and Mac calendar, in one place.")
        subtitle.font = KeenDesign.body(14)
        KeenDesign.label(subtitle, color: KeenDesign.inkMuted)

        let calendarGlass = KeenGlassSurface(cornerRadius: 20, tint: NSColor.white.withAlphaComponent(0.14))
        monthCalendar.onSelection = { [weak self] _ in self?.reloadAgenda() }
        monthCalendar.translatesAutoresizingMaskIntoConstraints = false
        calendarGlass.innerContentView.addSubview(monthCalendar)
        NSLayoutConstraint.activate([
            monthCalendar.leadingAnchor.constraint(equalTo: calendarGlass.innerContentView.leadingAnchor, constant: 18),
            monthCalendar.trailingAnchor.constraint(equalTo: calendarGlass.innerContentView.trailingAnchor, constant: -18),
            monthCalendar.topAnchor.constraint(equalTo: calendarGlass.innerContentView.topAnchor, constant: 18),
            monthCalendar.heightAnchor.constraint(equalToConstant: 304),
        ])

        let today = KeenGhostButton("Today", action: #selector(goToToday), target: self)
        let openPlan = KeenGhostButton("Open Plan", action: #selector(openPlan), target: self)
        let calendarActions = NSStackView(views: [today, openPlan])
        calendarActions.orientation = .horizontal
        calendarActions.spacing = 8
        calendarActions.translatesAutoresizingMaskIntoConstraints = false
        calendarGlass.innerContentView.addSubview(calendarActions)
        NSLayoutConstraint.activate([
            calendarActions.leadingAnchor.constraint(equalTo: monthCalendar.leadingAnchor),
            calendarActions.bottomAnchor.constraint(equalTo: calendarGlass.innerContentView.bottomAnchor, constant: -18),
            calendarActions.topAnchor.constraint(equalTo: monthCalendar.bottomAnchor, constant: 16),
        ])

        let agendaGlass = KeenGlassSurface(cornerRadius: 20, tint: NSColor.white.withAlphaComponent(0.14))
        selectedDateLabel.font = KeenDesign.title(18)
        KeenDesign.label(selectedDateLabel)
        agendaStack.orientation = .vertical
        agendaStack.alignment = .leading
        agendaStack.spacing = 8
        agendaStack.translatesAutoresizingMaskIntoConstraints = false

        let document = KeenFlippedView()
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
            scroll.topAnchor.constraint(equalTo: selectedDateLabel.bottomAnchor, constant: 14),
            scroll.bottomAnchor.constraint(equalTo: agendaHost.bottomAnchor, constant: -18),
        ])

        [title, subtitle, calendarGlass, agendaGlass].forEach { view.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            calendarGlass.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 18),
            calendarGlass.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            calendarGlass.heightAnchor.constraint(equalToConstant: 400),
            calendarGlass.widthAnchor.constraint(equalToConstant: 320),
            agendaGlass.topAnchor.constraint(equalTo: calendarGlass.topAnchor),
            agendaGlass.leadingAnchor.constraint(equalTo: calendarGlass.trailingAnchor, constant: 16),
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
        CalendarService.shared.onChange = { [weak self] in self?.reloadAgenda() }
        reloadAgenda()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let storeObserver {
            ScheduleStore.shared.removeObserver(storeObserver)
            self.storeObserver = nil
        }
        CalendarService.shared.onChange = nil
    }

    @objc private func goToToday() {
        monthCalendar.select(date: .now)
        reloadAgenda()
    }

    @objc private func openPlan() {
        MainWindowController.shared.showSection(.schedule)
    }

    @objc private func requestCalendarAccess() {
        Task { [weak self] in
            _ = await CalendarService.shared.requestAccess()
            self?.reloadAgenda()
        }
    }

    private func reloadAgenda() {
        let date = monthCalendar.selectedDate
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        selectedDateLabel.stringValue = formatter.string(from: date)
        agendaStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let reminders = ScheduleStore.shared.store.alarms
            .filter { $0.enabled && Calendar.autoupdatingCurrent.isDate($0.fireAt, inSameDayAs: date) }
            .sorted { $0.fireAt < $1.fireAt }
        let events = CalendarService.shared.events(on: date)

        if !CalendarService.shared.hasAccess {
            agendaStack.addArrangedSubview(helper("Optionally include events from Calendar. Sched works without access."))
            agendaStack.addArrangedSubview(accessButton)
        }

        for reminder in reminders {
            addAgendaRow(agendaRow(
                time: SchedTimeFormat.string(from: reminder.fireAt),
                title: reminder.title,
                detail: reminder.note.isEmpty ? "Sched reminder" : reminder.note,
                color: KeenDesign.levelColor(reminder.level),
                symbol: "bell.fill"
            ))
        }
        for event in events {
            let time = event.isAllDay ? "All day" : SchedTimeFormat.string(from: event.startDate)
            addAgendaRow(agendaRow(
                time: time,
                title: event.title ?? "Untitled event",
                detail: event.calendar.title,
                color: NSColor(cgColor: event.calendar.cgColor) ?? KeenDesign.accent,
                symbol: "calendar"
            ))
        }

        if reminders.isEmpty && events.isEmpty {
            agendaStack.addArrangedSubview(helper("Nothing scheduled for this day."))
        }
    }

    /// Width constraints are only valid after the row and stack share a view hierarchy.
    private func addAgendaRow(_ row: NSView) {
        agendaStack.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: agendaStack.widthAnchor).isActive = true
    }

    private func agendaRow(time: String, title: String, detail: String, color: NSColor, symbol: String) -> NSView {
        let row = KeenGlassSurface(cornerRadius: 12, tint: color.withAlphaComponent(0.10), interactive: false)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 66).isActive = true
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = color
        let timeLabel = NSTextField(labelWithString: time)
        timeLabel.font = KeenDesign.mono(11)
        KeenDesign.label(timeLabel, color: KeenDesign.inkMuted)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = KeenDesign.title(14)
        titleLabel.lineBreakMode = .byTruncatingTail
        KeenDesign.label(titleLabel)
        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = KeenDesign.body(11)
        detailLabel.lineBreakMode = .byTruncatingTail
        KeenDesign.label(detailLabel, color: KeenDesign.inkMuted)
        let text = NSStackView(views: [titleLabel, detailLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
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
            timeLabel.widthAnchor.constraint(equalToConstant: 64),
        ])
        return row
    }

    private func helper(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = KeenDesign.body(12)
        KeenDesign.label(label, color: KeenDesign.inkMuted)
        return label
    }
}

/// A native AppKit month grid sized for Sched's fixed window. `NSDatePicker`'s
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

        monthLabel.font = KeenDesign.title(17)
        KeenDesign.label(monthLabel)
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
            for _ in 0..<7 {
                let button = SchedDayButton()
                button.target = self
                button.action = #selector(daySelected(_:))
                button.heightAnchor.constraint(equalToConstant: 34).isActive = true
                dayButtons.append(button)
                row.addArrangedSubview(button)
            }
            weeks.addArrangedSubview(row)
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
        button.contentTintColor = KeenDesign.inkMuted
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
            label.font = KeenDesign.caption(10)
            KeenDesign.label(label, color: KeenDesign.inkMuted)
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
        font = KeenDesign.body(12)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func refreshStyle() {
        layer?.backgroundColor = isSelectedDate ? KeenDesign.accent.cgColor : NSColor.clear.cgColor
        layer?.borderWidth = isToday && !isSelectedDate ? 1.5 : 0
        layer?.borderColor = KeenDesign.accent.cgColor
        contentTintColor = isSelectedDate ? .white : (isInVisibleMonth ? KeenDesign.ink : KeenDesign.inkFaint)
        alphaValue = isInVisibleMonth ? 1 : 0.55
    }
}
