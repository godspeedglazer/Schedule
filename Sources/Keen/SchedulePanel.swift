import AppKit

@MainActor
final class SchedulePanelController: NSViewController, KeenAlarmCardDelegate {
    private let hero = KeenHeroStrip()
    private let listHeader = NSTextField(labelWithString: "Alarms")
    private let cardStack = NSStackView()
    private let listDocument = KeenFlippedView()
    private let scroll = NSScrollView()
    private let listEmpty = NSTextField(labelWithString: "No reminders yet. Add a daily or one-time reminder.\n“Make time visible.”")
    private let inspectorGlass = KeenGlassSurface(
        cornerRadius: KeenDesign.railCorner,
        tint: NSColor.white.withAlphaComponent(0.14)
    )
    private let mainColumn = NSView()
    private let inspectorScroll = NSScrollView()
    private var inspectorWidthConstraint: NSLayoutConstraint?
    private var listHeightConstraint: NSLayoutConstraint?
    private var heroTimer: Timer?
    private var selectedID: UUID?
    private var inspectorFields: [NSView] = []
    private var isLoadingInspector = false

    private let titleGlass = KeenGlassField(placeholder: "Morning focus")
    private let noteGlass = KeenGlassField(placeholder: "What should future-you know?")
    private var titleField: NSTextField { titleGlass.field }
    private var noteField: NSTextField { noteGlass.field }
    private let datePicker = NSDatePicker()
    private let levelPopup = NSPopUpButton()
    private let repeatCheck = NSButton(checkboxWithTitle: "Repeats every day", target: nil, action: nil)
    private let enabledCheck = NSButton(checkboxWithTitle: "Active", target: nil, action: nil)
    private let actionPopup = NSPopUpButton()
    private let actionGlass = KeenGlassField(placeholder: "Shortcut name")
    private var actionField: NSTextField { actionGlass.field }
    private let actionAppPopup = keenAppPopup()
    private let refreshActionAppsButton = KeenGhostButton("Refresh", action: #selector(reloadActionAppsMenu), target: nil)
    private let actionPayloadLabel = keenFieldLabel("Shortcut name")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "Choose a reminder to shape its message, timing, and follow-up action.")

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear

        let title = NSTextField(labelWithString: "Plan")
        title.font = KeenDesign.display(28)
        KeenDesign.label(title)
        let sub = NSTextField(labelWithString: "Upcoming reminders and actions.")
        sub.font = KeenDesign.body(14)
        KeenDesign.label(sub, color: KeenDesign.inkMuted)

        let toolbarGlass = KeenGlassSurface(cornerRadius: 12, tint: NSColor.white.withAlphaComponent(0.08))
        let addDaily = KeenPrimaryButton("＋ Daily", action: #selector(addDaily), target: self)
        let addOnce = KeenGhostButton("One-time", action: #selector(addOneShot), target: self)
        let del = KeenGhostButton("Delete", action: #selector(deleteSelected), target: self)
        for btn in [addDaily, addOnce, del] {
            btn.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        let toolbar = NSStackView(views: [addDaily, addOnce, del])
        toolbar.orientation = .horizontal
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbarGlass.innerContentView.addSubview(toolbar)
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: toolbarGlass.innerContentView.leadingAnchor, constant: 10),
            toolbar.trailingAnchor.constraint(equalTo: toolbarGlass.innerContentView.trailingAnchor, constant: -10),
            toolbar.topAnchor.constraint(equalTo: toolbarGlass.innerContentView.topAnchor, constant: 6),
            toolbar.bottomAnchor.constraint(equalTo: toolbarGlass.innerContentView.bottomAnchor, constant: -6),
        ])

        listHeader.font = KeenDesign.section(11)
        KeenDesign.label(listHeader, color: KeenDesign.inkFaint)

        listEmpty.font = KeenDesign.body(13)
        listEmpty.textColor = KeenDesign.inkFaint
        listEmpty.alignment = .center
        listEmpty.maximumNumberOfLines = 3
        listEmpty.isHidden = true
        listEmpty.translatesAutoresizingMaskIntoConstraints = false

        cardStack.orientation = .vertical
        cardStack.spacing = 8
        cardStack.alignment = .leading
        cardStack.distribution = .fill
        cardStack.translatesAutoresizingMaskIntoConstraints = false

        listDocument.translatesAutoresizingMaskIntoConstraints = false
        listDocument.addSubview(cardStack)
        listDocument.addSubview(listEmpty)
        NSLayoutConstraint.activate([
            cardStack.leadingAnchor.constraint(equalTo: listDocument.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: listDocument.trailingAnchor),
            cardStack.topAnchor.constraint(equalTo: listDocument.topAnchor),
            listDocument.bottomAnchor.constraint(equalTo: cardStack.bottomAnchor, constant: 8),
            listEmpty.centerXAnchor.constraint(equalTo: listDocument.centerXAnchor),
            listEmpty.centerYAnchor.constraint(equalTo: listDocument.centerYAnchor),
            listEmpty.widthAnchor.constraint(lessThanOrEqualTo: listDocument.widthAnchor, constant: -40),
        ])

        scroll.documentView = listDocument
        schedConfigureScroll(scroll)
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
        scroll.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 16, right: 0)
        scroll.clipsToBounds = true

        if let clip = scroll.contentView as NSClipView? {
            NSLayoutConstraint.activate([
                listDocument.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
                listDocument.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
                listDocument.topAnchor.constraint(equalTo: clip.topAnchor),
                listDocument.widthAnchor.constraint(equalTo: clip.widthAnchor),
            ])
        }

        let widthConstraint = inspectorGlass.widthAnchor.constraint(equalToConstant: KeenDesign.inspectorWidth)
        widthConstraint.isActive = true
        inspectorWidthConstraint = widthConstraint
        buildInspector()

        mainColumn.translatesAutoresizingMaskIntoConstraints = false
        inspectorGlass.translatesAutoresizingMaskIntoConstraints = false
        toolbarGlass.translatesAutoresizingMaskIntoConstraints = false
        toolbarGlass.setContentCompressionResistancePriority(.required, for: .horizontal)

        [title, sub, toolbarGlass, hero, listHeader, scroll].forEach {
            mainColumn.addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        view.addSubview(mainColumn)
        view.addSubview(inspectorGlass)

        let mainToInspector = mainColumn.trailingAnchor.constraint(equalTo: inspectorGlass.leadingAnchor, constant: -KeenDesign.contentGap)
        mainToInspector.priority = .required

        NSLayoutConstraint.activate([
            mainColumn.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mainColumn.topAnchor.constraint(equalTo: view.topAnchor),
            mainColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            mainToInspector,

            inspectorGlass.topAnchor.constraint(equalTo: view.topAnchor),
            inspectorGlass.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            inspectorGlass.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            title.topAnchor.constraint(equalTo: mainColumn.topAnchor, constant: 2),
            title.leadingAnchor.constraint(equalTo: mainColumn.leadingAnchor),
            sub.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            sub.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            sub.trailingAnchor.constraint(equalTo: mainColumn.trailingAnchor),
            toolbarGlass.topAnchor.constraint(equalTo: sub.bottomAnchor, constant: 14),
            toolbarGlass.leadingAnchor.constraint(equalTo: mainColumn.leadingAnchor),
            toolbarGlass.trailingAnchor.constraint(lessThanOrEqualTo: mainColumn.trailingAnchor),
            hero.topAnchor.constraint(equalTo: toolbarGlass.bottomAnchor, constant: 16),
            hero.leadingAnchor.constraint(equalTo: mainColumn.leadingAnchor),
            hero.trailingAnchor.constraint(equalTo: mainColumn.trailingAnchor),
            listHeader.topAnchor.constraint(equalTo: hero.bottomAnchor, constant: 16),
            listHeader.leadingAnchor.constraint(equalTo: mainColumn.leadingAnchor, constant: 2),
            scroll.topAnchor.constraint(equalTo: listHeader.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: mainColumn.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: mainColumn.trailingAnchor),
            scroll.bottomAnchor.constraint(lessThanOrEqualTo: mainColumn.bottomAnchor, constant: -8),
        ])
        let listHeight = scroll.heightAnchor.constraint(equalToConstant: 100)
        listHeight.isActive = true
        listHeightConstraint = listHeight

        ScheduleStore.shared.onChange = { [weak self] in
            self?.hero.refresh()
            self?.rebuildAlarmList()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        heroTimer?.invalidate()
        heroTimer = nil
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        heroTimer?.invalidate()
        heroTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.hero.refresh() }
        }
        rebuildAlarmList()
        reloadActionAppsMenu()
    }

    private func buildInspector() {
        schedConfigureScroll(inspectorScroll)

        let inspectorDocument = KeenFlippedView()
        inspectorDocument.translatesAutoresizingMaskIntoConstraints = false
        inspectorScroll.documentView = inspectorDocument

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = KeenDesign.body(13)
        KeenDesign.label(emptyLabel, color: KeenDesign.inkFaint)

        let inspectorTitle = NSTextField(labelWithString: "Reminder details")
        inspectorTitle.font = KeenDesign.title(18)
        KeenDesign.label(inspectorTitle)
        let closeInspectorButton = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close reminder details") ?? NSImage(),
            target: self,
            action: #selector(closeInspector)
        )
        closeInspectorButton.isBordered = false
        closeInspectorButton.contentTintColor = KeenDesign.inkMuted
        closeInspectorButton.toolTip = "Close reminder details"
        let inspectorHeaderSpacer = NSView()
        inspectorHeaderSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let inspectorHeader = NSStackView(views: [inspectorTitle, inspectorHeaderSpacer, closeInspectorButton])
        inspectorHeader.orientation = .horizontal
        inspectorHeader.alignment = .centerY
        inspectorHeader.widthAnchor.constraint(equalToConstant: KeenDesign.inspectorWidth - 32).isActive = true
        let inspectorHelp = NSTextField(wrappingLabelWithString: "Write the message you’ll want to see when this moment arrives.")
        inspectorHelp.font = KeenDesign.body(12)
        KeenDesign.label(inspectorHelp, color: KeenDesign.inkMuted)
        inspectorHelp.preferredMaxLayoutWidth = KeenDesign.inspectorWidth - 32

        datePicker.datePickerElements = [.yearMonthDay, .hourMinute]
        datePicker.datePickerStyle = .textFieldAndStepper
        schedStyleSelector(datePicker)

        levelPopup.removeAllItems()
        InterventionLevel.allCases.forEach { levelPopup.addItem(withTitle: "\($0.label) — \($0.detail)") }
        schedStyleSelector(levelPopup)
        levelPopup.target = self
        levelPopup.action = #selector(saveInspector)
        actionPopup.removeAllItems()
        for kind in KeenActionKind.userFacingCases {
            actionPopup.addItem(withTitle: kind.displayName)
        }
        actionPopup.target = self
        actionPopup.action = #selector(actionKindChanged)
        schedStyleSelector(actionPopup)
        schedStyleSelector(actionAppPopup)
        actionAppPopup.target = self
        actionAppPopup.action = #selector(saveInspector)

        datePicker.target = self
        datePicker.action = #selector(saveInspector)
        repeatCheck.target = self
        repeatCheck.action = #selector(saveInspector)
        enabledCheck.target = self
        enabledCheck.action = #selector(saveInspector)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(inspectorTextDidEndEditing(_:)),
            name: NSControl.textDidEndEditingNotification,
            object: nil
        )

        enabledCheck.state = .on

        refreshActionAppsButton.target = self
        actionAppPopup.isHidden = true
        refreshActionAppsButton.isHidden = true

        let autoSave = NSTextField(labelWithString: "Changes save automatically")
        autoSave.font = KeenDesign.caption(11)
        KeenDesign.label(autoSave, color: KeenDesign.inkFaint)

        let rows: [NSView] = [
            keenFieldLabel("Name"), titleGlass,
            keenFieldLabel("Note"), noteGlass,
            keenFieldLabel("When"), datePicker,
            keenFieldLabel("Intensity"), levelPopup,
            repeatCheck, enabledCheck,
            keenFieldLabel("Then run"), actionPopup,
            actionPayloadLabel, actionGlass, actionAppPopup, refreshActionAppsButton,
            autoSave,
        ]
        inspectorFields = rows
        stack.addArrangedSubview(inspectorHeader)
        stack.addArrangedSubview(inspectorHelp)
        stack.setCustomSpacing(16, after: inspectorHelp)
        stack.addArrangedSubview(emptyLabel)
        for row in rows {
            stack.addArrangedSubview(row)
            if row is KeenGlassField || row is NSPopUpButton || row is NSDatePicker {
                row.widthAnchor.constraint(equalToConstant: KeenDesign.inspectorWidth - 32).isActive = true
            }
        }

        inspectorDocument.addSubview(stack)
        inspectorGlass.innerContentView.addSubview(inspectorScroll)
        NSLayoutConstraint.activate([
            inspectorScroll.leadingAnchor.constraint(equalTo: inspectorGlass.innerContentView.leadingAnchor),
            inspectorScroll.trailingAnchor.constraint(equalTo: inspectorGlass.innerContentView.trailingAnchor),
            inspectorScroll.topAnchor.constraint(equalTo: inspectorGlass.innerContentView.topAnchor),
            inspectorScroll.bottomAnchor.constraint(equalTo: inspectorGlass.innerContentView.bottomAnchor),
            stack.topAnchor.constraint(equalTo: inspectorDocument.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: inspectorDocument.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: inspectorDocument.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: inspectorDocument.bottomAnchor, constant: -16),
        ])
        if let clip = inspectorScroll.contentView as NSClipView? {
            NSLayoutConstraint.activate([
                inspectorDocument.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
                inspectorDocument.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
                inspectorDocument.topAnchor.constraint(equalTo: clip.topAnchor),
                inspectorDocument.widthAnchor.constraint(equalTo: clip.widthAnchor),
            ])
        }
        setInspectorVisible(false)
    }

    private func setInspectorVisible(_ on: Bool) {
        guard let inspectorWidthConstraint else { return }
        inspectorWidthConstraint.constant = on ? KeenDesign.inspectorWidth : 0
        inspectorGlass.isHidden = !on
        inspectorGlass.alphaValue = 1
        emptyLabel.isHidden = on
        inspectorFields.forEach { $0.isHidden = !on }
    }

    private func pruneStaleAlarms() {
        for alarm in ScheduleStore.shared.store.alarms
            where !alarm.enabled && !alarm.repeatDaily && alarm.pausedRemainingSeconds == nil {
            ScheduleStore.shared.remove(id: alarm.id, broadcast: false)
        }
    }

    private func sortedAlarms() -> [KeenAlarm] {
        pruneStaleAlarms()
        return ScheduleStore.shared.store.alarms
            .filter(\.enabled)
            .sorted { $0.fireAt < $1.fireAt }
    }

    private func rebuildAlarmList() {
        guard view.window != nil else { return }
        hero.refresh()

        if let selectedID,
           !ScheduleStore.shared.store.alarms.contains(where: { $0.id == selectedID }) {
            self.selectedID = nil
        }

        var existingCards: [UUID: KeenAlarmCard] = [:]
        for case let card as KeenAlarmCard in cardStack.arrangedSubviews {
            existingCards[card.alarmID] = card
        }
        cardStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let alarms = sortedAlarms()
        listEmpty.isHidden = !alarms.isEmpty
        listHeightConstraint?.constant = min(320, max(100, CGFloat(alarms.count * 84 + 8)))

        for alarm in alarms {
            let card: KeenAlarmCard
            if let reused = existingCards[alarm.id] {
                card = reused
                card.refresh(alarm: alarm, selected: alarm.id == selectedID)
            } else {
                card = KeenAlarmCard(alarm: alarm, selected: alarm.id == selectedID)
            }
            card.cardDelegate = self
            cardStack.addArrangedSubview(card)
            card.leadingAnchor.constraint(equalTo: cardStack.leadingAnchor).isActive = true
            card.trailingAnchor.constraint(equalTo: cardStack.trailingAnchor).isActive = true
        }

        listDocument.layoutSubtreeIfNeeded()
        scroll.reflectScrolledClipView(scroll.contentView)

        reloadInspector()
    }

    private func updateSelectionHighlight() {
        for case let card as KeenAlarmCard in cardStack.arrangedSubviews {
            card.setSelected(card.alarmID == selectedID)
        }
    }

    func alarmCardSelected(_ id: UUID) {
        selectedID = selectedID == id ? nil : id
        updateSelectionHighlight()
        reloadInspector()
    }

    @objc private func closeInspector() {
        view.window?.makeFirstResponder(nil)
        selectedID = nil
        updateSelectionHighlight()
        reloadInspector()
    }

    private func reloadInspector() {
        let has = selectedID != nil
        setInspectorVisible(has)
        guard let id = selectedID, let alarm = ScheduleStore.shared.store.alarms.first(where: { $0.id == id }) else { return }
        isLoadingInspector = true
        titleField.stringValue = alarm.title
        noteField.stringValue = alarm.note
        datePicker.dateValue = alarm.fireAt
        levelPopup.selectItem(at: InterventionLevel.allCases.firstIndex(of: alarm.level) ?? 0)
        repeatCheck.state = alarm.repeatDaily ? .on : .off
        enabledCheck.state = alarm.enabled ? .on : .off
        actionPopup.selectItem(at: KeenActionKind.userFacingCases.firstIndex(of: alarm.action.kind) ?? 0)
        actionField.stringValue = alarm.action.payload
        updateActionFieldLabel()
        if alarm.action.kind == .quitApp {
            RunningApps.populate(actionAppPopup, selectedBundleId: nil, selectedName: alarm.action.payload)
        }
        isLoadingInspector = false
    }

    @objc private func reloadActionAppsMenu() {
        let name = actionField.stringValue
        RunningApps.populate(actionAppPopup, selectedBundleId: nil, selectedName: name.isEmpty ? nil : name)
    }

    private func actionPayload() -> String {
        let kind = KeenActionKind.userFacingCases[actionPopup.indexOfSelectedItem]
        if kind == .quitApp, let app = RunningApps.selectedApp(from: actionAppPopup) {
            return app.name
        }
        return actionField.stringValue
    }

    @objc private func actionKindChanged() {
        updateActionFieldLabel()
        saveInspector()
    }

    @objc private func inspectorTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field === titleField || field === noteField || field === actionField else { return }
        saveInspector()
    }

    private func updateActionFieldLabel() {
        let kind = KeenActionKind.userFacingCases[actionPopup.indexOfSelectedItem]
        let label: String
        let placeholder: String
        let isQuit = kind == .quitApp
        let needsText = kind == .shortcut || kind == .url
        actionPayloadLabel.isHidden = !needsText && !isQuit
        actionGlass.isHidden = !needsText
        actionAppPopup.isHidden = !isQuit
        refreshActionAppsButton.isHidden = !isQuit
        switch kind {
        case .none:
            label = "Action detail"
            placeholder = "Not used"
        case .shortcut:
            label = "Shortcut name"
            placeholder = "e.g. Start Focus"
        case .url:
            label = "URL"
            placeholder = "https://…"
        case .quitApp:
            label = "App to quit"
            placeholder = ""
            reloadActionAppsMenu()
        case .shell:
            label = "Action detail"
            placeholder = "Not available"
        }
        actionPayloadLabel.stringValue = label
        actionField.placeholderString = placeholder
        actionField.isEnabled = kind != .none && !isQuit
    }

    @objc private func saveInspector() {
        guard !isLoadingInspector, let id = selectedID,
              var alarm = ScheduleStore.shared.store.alarms.first(where: { $0.id == id }) else { return }
        let cleanTitle = KeenTextLimits.clean(titleField.stringValue, limit: KeenTextLimits.title)
        alarm.title = cleanTitle.isEmpty ? "Alarm" : cleanTitle
        alarm.note = KeenTextLimits.clean(noteField.stringValue, limit: KeenTextLimits.note)
        alarm.fireAt = datePicker.dateValue
        alarm.level = InterventionLevel.allCases[levelPopup.indexOfSelectedItem]
        alarm.repeatDaily = repeatCheck.state == .on
        alarm.enabled = enabledCheck.state == .on
        alarm.action = KeenAction.from(
            kind: KeenActionKind.userFacingCases[actionPopup.indexOfSelectedItem],
            payload: KeenTextLimits.clean(actionPayload(), limit: KeenTextLimits.action)
        )
        ScheduleStore.shared.upsert(alarm, notifyOnChange: false)
        hero.refresh()
        if let card = cardStack.arrangedSubviews
            .compactMap({ $0 as? KeenAlarmCard })
            .first(where: { $0.alarmID == alarm.id }) {
            card.refresh(alarm: alarm, selected: true)
        }
    }

    @objc private func addDaily() {
        let cal = Calendar.current
        var c = cal.dateComponents([.year, .month, .day], from: .now)
        c.hour = 9; c.minute = 0
        var fireAt = cal.date(from: c) ?? .now
        if fireAt <= .now {
            fireAt = cal.date(byAdding: .day, value: 1, to: fireAt) ?? Date().addingTimeInterval(86400)
        }
        let alarm = KeenAlarm(title: "New daily", fireAt: fireAt, level: ScheduleStore.shared.store.defaultLevel, repeatDaily: true)
        selectedID = alarm.id
        ScheduleStore.shared.upsert(alarm)
        view.window?.makeFirstResponder(titleField)
    }

    @objc private func addOneShot() {
        let alarm = KeenAlarm(title: "New reminder", fireAt: Date().addingTimeInterval(1800), level: ScheduleStore.shared.store.defaultLevel)
        selectedID = alarm.id
        ScheduleStore.shared.upsert(alarm)
        view.window?.makeFirstResponder(titleField)
    }

    @objc private func deleteSelected() {
        guard let id = selectedID else { return }
        selectedID = nil
        ScheduleStore.shared.remove(id: id)
    }
}
