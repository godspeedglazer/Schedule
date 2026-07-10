import AppKit
import EventKit

@MainActor
final class CalendarPanelController: NSViewController {
    private let datePicker = NSDatePicker()
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
        datePicker.datePickerStyle = .clockAndCalendar
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.dateValue = .now
        datePicker.isBordered = false
        datePicker.target = self
        datePicker.action = #selector(dateChanged)
        datePicker.translatesAutoresizingMaskIntoConstraints = false
        calendarGlass.innerContentView.addSubview(datePicker)
        NSLayoutConstraint.activate([
            datePicker.leadingAnchor.constraint(equalTo: calendarGlass.innerContentView.leadingAnchor, constant: 18),
            datePicker.trailingAnchor.constraint(equalTo: calendarGlass.innerContentView.trailingAnchor, constant: -18),
            datePicker.topAnchor.constraint(equalTo: calendarGlass.innerContentView.topAnchor, constant: 18),
            datePicker.heightAnchor.constraint(equalToConstant: 250),
        ])

        let today = KeenGhostButton("Today", action: #selector(goToToday), target: self)
        let openPlan = KeenGhostButton("Open Plan", action: #selector(openPlan), target: self)
        let calendarActions = NSStackView(views: [today, openPlan])
        calendarActions.orientation = .horizontal
        calendarActions.spacing = 8
        calendarActions.translatesAutoresizingMaskIntoConstraints = false
        calendarGlass.innerContentView.addSubview(calendarActions)
        NSLayoutConstraint.activate([
            calendarActions.leadingAnchor.constraint(equalTo: datePicker.leadingAnchor),
            calendarActions.bottomAnchor.constraint(equalTo: calendarGlass.innerContentView.bottomAnchor, constant: -18),
            calendarActions.topAnchor.constraint(greaterThanOrEqualTo: datePicker.bottomAnchor, constant: 12),
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
            calendarGlass.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            calendarGlass.widthAnchor.constraint(equalToConstant: 320),
            agendaGlass.topAnchor.constraint(equalTo: calendarGlass.topAnchor),
            agendaGlass.leadingAnchor.constraint(equalTo: calendarGlass.trailingAnchor, constant: 16),
            agendaGlass.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            agendaGlass.bottomAnchor.constraint(equalTo: calendarGlass.bottomAnchor),
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

    @objc private func dateChanged() { reloadAgenda() }

    @objc private func goToToday() {
        datePicker.dateValue = .now
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
        let date = datePicker.dateValue
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
