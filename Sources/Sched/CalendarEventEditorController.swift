import AppKit
import EventKit

@MainActor
final class CalendarEventEditorController: NSViewController {
    struct Seed {
        var title: String
        var startDate: Date
        var endDate: Date
        var isAllDay: Bool
        var calendarIdentifier: String?
        var location: String
        var notes: String

        static func newEvent(on date: Date) -> Seed {
            let calendar = Calendar.autoupdatingCurrent
            let now = Date()
            let start: Date
            if calendar.isDateInToday(date) {
                let rounded = calendar.date(bySetting: .minute, value: 0, of: now.addingTimeInterval(3600)) ?? now.addingTimeInterval(3600)
                start = rounded
            } else {
                start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
            }
            return Seed(
                title: "",
                startDate: start,
                endDate: start.addingTimeInterval(3600),
                isAllDay: false,
                calendarIdentifier: CalendarService.shared.defaultCalendarIdentifier,
                location: "",
                notes: ""
            )
        }

        static func reminder(_ alarm: SchedAlarm) -> Seed {
            Seed(
                title: alarm.title,
                startDate: alarm.fireAt,
                endDate: alarm.fireAt.addingTimeInterval(30 * 60),
                isAllDay: false,
                calendarIdentifier: CalendarService.shared.defaultCalendarIdentifier,
                location: "",
                notes: alarm.note
            )
        }
    }

    private let seed: Seed
    private let onSave: (EKEvent) -> Void
    private weak var sheetWindow: NSWindow?
    private weak var parentWindow: NSWindow?

    private let titleField = NSTextField()
    private let startPicker = NSDatePicker()
    private let endPicker = NSDatePicker()
    private let allDayCheck = NSButton(checkboxWithTitle: "All-day", target: nil, action: nil)
    private let calendarPopup = NSPopUpButton()
    private let locationField = NSTextField()
    private let notesField = NSTextField()

    private init(seed: Seed, onSave: @escaping (EKEvent) -> Void) {
        self.seed = seed
        self.onSave = onSave
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    static func present(from parent: NSWindow, seed: Seed, onSave: @escaping (EKEvent) -> Void = { _ in }) {
        Task { @MainActor in
            if !CalendarService.shared.hasAccess {
                let granted = await CalendarService.shared.requestAccess()
                guard granted else {
                    let alert = NSAlert()
                    alert.messageText = "Calendar Access Required"
                    alert.informativeText = "Allow Sched full Calendar access to create and display events."
                    alert.alertStyle = .informational
                    alert.beginSheetModal(for: parent, completionHandler: nil)
                    return
                }
            }

            let controller = CalendarEventEditorController(seed: seed, onSave: onSave)
            let sheet = NSWindow(contentViewController: controller)
            sheet.title = "New Calendar Event"
            sheet.styleMask = [.titled, .closable]
            sheet.setContentSize(NSSize(width: 460, height: 420))
            controller.sheetWindow = sheet
            controller.parentWindow = parent
            parent.beginSheet(sheet)
        }
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = SchedDesign.canvas.cgColor

        let heading = NSTextField(labelWithString: "New event")
        heading.font = SchedDesign.display(24)
        SchedDesign.label(heading)
        let help = NSTextField(labelWithString: "Add directly to your Mac calendar.")
        help.font = SchedDesign.body(12)
        SchedDesign.label(help, color: SchedDesign.inkMuted)

        configureTextField(titleField, placeholder: "Event title")
        configureTextField(locationField, placeholder: "Optional location")
        configureTextField(notesField, placeholder: "Optional notes")
        notesField.usesSingleLineMode = false
        notesField.cell?.wraps = true
        notesField.cell?.isScrollable = false
        notesField.heightAnchor.constraint(equalToConstant: 64).isActive = true

        for picker in [startPicker, endPicker] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = [.yearMonthDay, .hourMinute]
            picker.translatesAutoresizingMaskIntoConstraints = false
        }

        schedStyleSelector(calendarPopup)
        calendarPopup.removeAllItems()
        for calendar in CalendarService.shared.writableCalendars() {
            calendarPopup.addItem(withTitle: calendar.title)
            calendarPopup.lastItem?.representedObject = calendar.identifier
        }

        allDayCheck.target = self
        allDayCheck.action = #selector(allDayChanged)

        let fields = NSStackView()
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 8
        fields.translatesAutoresizingMaskIntoConstraints = false
        fields.addArrangedSubview(fieldRow("Title", titleField))
        fields.addArrangedSubview(fieldRow("Starts", startPicker))
        fields.addArrangedSubview(fieldRow("Ends", endPicker))
        fields.addArrangedSubview(fieldRow("Calendar", calendarPopup))
        fields.addArrangedSubview(fieldRow("Location", locationField))
        fields.addArrangedSubview(fieldRow("Notes", notesField))
        fields.addArrangedSubview(allDayCheck)

        let cancel = SchedGhostButton("Cancel", action: #selector(cancel), target: self)
        let add = SchedPrimaryButton("Add Event", action: #selector(save), target: self)
        let buttonSpacer = NSView()
        buttonSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [buttonSpacer, cancel, add])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        buttons.translatesAutoresizingMaskIntoConstraints = false

        [heading, help, fields, buttons].forEach { view.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            heading.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            heading.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            heading.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            help.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            help.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 3),
            fields.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            fields.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            fields.topAnchor.constraint(equalTo: help.bottomAnchor, constant: 18),
            buttons.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            buttons.trailingAnchor.constraint(equalTo: heading.trailingAnchor),
            buttons.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -20),
            fields.bottomAnchor.constraint(lessThanOrEqualTo: buttons.topAnchor, constant: -16),
        ])

        titleField.stringValue = seed.title
        startPicker.dateValue = seed.startDate
        endPicker.dateValue = seed.endDate
        allDayCheck.state = seed.isAllDay ? .on : .off
        locationField.stringValue = seed.location
        notesField.stringValue = seed.notes
        let preferredCalendar = seed.calendarIdentifier ?? CalendarService.shared.defaultCalendarIdentifier
        if let identifier = preferredCalendar,
           let index = calendarPopup.itemArray.firstIndex(where: { ($0.representedObject as? String) == identifier }) {
            calendarPopup.selectItem(at: index)
        }
        updateDatePickerMode()

        DispatchQueue.main.async { [weak self] in self?.view.window?.makeFirstResponder(self?.titleField) }
    }

    private func fieldRow(_ label: String, _ control: NSView) -> NSView {
        let labelView = NSTextField(labelWithString: label)
        labelView.font = SchedDesign.body(12)
        labelView.alignment = .right
        SchedDesign.label(labelView, color: SchedDesign.inkMuted)
        labelView.translatesAutoresizingMaskIntoConstraints = false
        labelView.widthAnchor.constraint(equalToConstant: 62).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [labelView, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(greaterThanOrEqualToConstant: 310).isActive = true
        return row
    }

    private func configureTextField(_ field: NSTextField, placeholder: String) {
        field.placeholderString = placeholder
        field.font = SchedDesign.body(13)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.translatesAutoresizingMaskIntoConstraints = false
        if field !== notesField {
            field.heightAnchor.constraint(equalToConstant: 30).isActive = true
        }
    }

    @objc private func allDayChanged() {
        updateDatePickerMode()
    }

    private func updateDatePickerMode() {
        let elements: NSDatePicker.ElementFlags = allDayCheck.state == .on ? [.yearMonthDay] : [.yearMonthDay, .hourMinute]
        startPicker.datePickerElements = elements
        endPicker.datePickerElements = elements
    }

    @objc private func cancel() {
        guard let parentWindow, let sheetWindow else { return }
        parentWindow.endSheet(sheetWindow)
    }

    @objc private func save() {
        let title = SchedTextLimits.clean(titleField.stringValue, limit: SchedTextLimits.title)
        guard !title.isEmpty else {
            NSSound.beep()
            view.window?.makeFirstResponder(titleField)
            return
        }

        let draft = CalendarEventDraft(
            title: title,
            startDate: startPicker.dateValue,
            endDate: endPicker.dateValue,
            isAllDay: allDayCheck.state == .on,
            calendarIdentifier: calendarPopup.selectedItem?.representedObject as? String,
            location: locationField.stringValue,
            notes: notesField.stringValue
        )

        do {
            let event = try CalendarService.shared.createEvent(draft)
            onSave(event)
            cancel()
        } catch {
            let alert = NSAlert(error: error)
            if let window = view.window { alert.beginSheetModal(for: window, completionHandler: nil) }
        }
    }
}
