import AppKit

@MainActor
final class SchedulePanelController: NSViewController, SchedAlarmCardDelegate {
    private let hero = SchedHeroStrip()
    private let listHeader = NSTextField(labelWithString: "Alarms")
    private let cardStack = NSStackView()
    private let listDocument = SchedFlippedView()
    private let scroll = NSScrollView()
    private let listEmpty = NSTextField(labelWithString: "No reminders yet. Add a daily or one-time reminder.\n“Make time visible.”")
    private let inspectorGlass = SchedGlassSurface(
        cornerRadius: SchedDesign.railCorner,
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

    private let titleGlass = SchedGlassField(placeholder: "Morning focus")
    private let noteGlass = SchedGlassField(placeholder: "What should future-you know?")
    private var titleField: NSTextField { titleGlass.field }
    private var noteField: NSTextField { noteGlass.field }
    private let datePicker = NSDatePicker()
    private let levelPopup = NSPopUpButton()
    private let soundPopup = NSPopUpButton()
    private let previewSoundButton = SchedGhostButton("Preview Sound", action: #selector(previewInspectorSound), target: nil)
    private let repeatCheck = NSButton(checkboxWithTitle: "Repeats every day", target: nil, action: nil)
    private let enabledCheck = NSButton(checkboxWithTitle: "Active", target: nil, action: nil)
    private let actionPopup = NSPopUpButton()
    private let actionGlass = SchedGlassField(placeholder: "Shortcut name")
    private var actionField: NSTextField { actionGlass.field }
    private let actionAppPopup = schedAppPopup()
    private let refreshActionAppsButton = SchedGhostButton("Refresh", action: #selector(reloadActionAppsMenu), target: nil)
    private let actionPayloadLabel = schedFieldLabel("Shortcut name")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "Choose a reminder to shape its message, timing, and follow-up action.")

    func selectAlarm(_ id: UUID) {
        guard ScheduleStore.shared.store.alarms.contains(where: { $0.id == id }) else { return }
        selectedID = id
        if isViewLoaded {
            updateSelectionHighlight()
            reloadInspector()
        }
    }

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear

        let title = NSTextField(labelWithString: "Plan")
        title.font = SchedDesign.display(28)
        SchedDesign.label(title)
        let sub = NSTextField(labelWithString: "Upcoming reminders and actions.")
        sub.font = SchedDesign.body(14)
        SchedDesign.label(sub, color: SchedDesign.inkMuted)

        let toolbarGlass = SchedGlassSurface(cornerRadius: 12, tint: NSColor.white.withAlphaComponent(0.08))
        let addDaily = SchedPrimaryButton("＋ Daily", action: #selector(addDaily), target: self)
        let addOnce = SchedGhostButton("One-time", action: #selector(addOneShot), target: self)
        let del = SchedGhostButton("Delete", action: #selector(deleteSelected), target: self)
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

        listHeader.font = SchedDesign.section(11)
        SchedDesign.label(listHeader, color: SchedDesign.inkFaint)

        listEmpty.font = SchedDesign.body(13)
        listEmpty.textColor = SchedDesign.inkFaint
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

        let widthConstraint = inspectorGlass.widthAnchor.constraint(equalToConstant: SchedDesign.inspectorWidth)
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

        let mainToInspector = mainColumn.trailingAnchor.constraint(equalTo: inspectorGlass.leadingAnchor, constant: -SchedDesign.contentGap)
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

        let inspectorDocument = SchedFlippedView()
        inspectorDocument.translatesAutoresizingMaskIntoConstraints = false
        inspectorScroll.documentView = inspectorDocument

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = SchedDesign.body(13)
        SchedDesign.label(emptyLabel, color: SchedDesign.inkFaint)

        let inspectorTitle = NSTextField(labelWithString: "Reminder details")
        inspectorTitle.font = SchedDesign.title(18)
        SchedDesign.label(inspectorTitle)
        let closeInspectorButton = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Close reminder details") ?? NSImage(),
            target: self,
            action: #selector(closeInspector)
        )
        closeInspectorButton.isBordered = false
        closeInspectorButton.contentTintColor = SchedDesign.inkMuted
        closeInspectorButton.toolTip = "Close reminder details"
        let inspectorHeaderSpacer = NSView()
        inspectorHeaderSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let inspectorHeader = NSStackView(views: [inspectorTitle, inspectorHeaderSpacer, closeInspectorButton])
        inspectorHeader.orientation = .horizontal
        inspectorHeader.alignment = .centerY
        inspectorHeader.widthAnchor.constraint(equalToConstant: SchedDesign.inspectorWidth - 32).isActive = true
        let inspectorHelp = NSTextField(wrappingLabelWithString: "Write the message you’ll want to see when this moment arrives.")
        inspectorHelp.font = SchedDesign.body(12)
        SchedDesign.label(inspectorHelp, color: SchedDesign.inkMuted)
        inspectorHelp.preferredMaxLayoutWidth = SchedDesign.inspectorWidth - 32

        datePicker.datePickerElements = [.yearMonthDay, .hourMinute]
        datePicker.datePickerStyle = .textFieldAndStepper
        schedStyleSelector(datePicker)

        levelPopup.removeAllItems()
        InterventionLevel.allCases.forEach { levelPopup.addItem(withTitle: "\($0.label) — \($0.detail)") }
        schedStyleSelector(levelPopup)
        levelPopup.target = self
        levelPopup.action = #selector(saveInspector)
        schedStyleSelector(soundPopup)
        soundPopup.target = self
        soundPopup.action = #selector(saveInspector)
        previewSoundButton.target = self
        reloadSoundChoices(selected: nil)
        actionPopup.removeAllItems()
        for kind in SchedActionKind.userFacingCases {
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
        autoSave.font = SchedDesign.caption(11)
        SchedDesign.label(autoSave, color: SchedDesign.inkFaint)

        let rows: [NSView] = [
            schedFieldLabel("Name"), titleGlass,
            schedFieldLabel("Note"), noteGlass,
            schedFieldLabel("When"), datePicker,
            schedFieldLabel("Intensity"), levelPopup,
            schedFieldLabel("Sound"), soundPopup, previewSoundButton,
            repeatCheck, enabledCheck,
            schedFieldLabel("Then run"), actionPopup,
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
            if row is SchedGlassField || row is NSPopUpButton || row is NSDatePicker {
                row.widthAnchor.constraint(equalToConstant: SchedDesign.inspectorWidth - 32).isActive = true
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
        inspectorWidthConstraint.constant = on ? SchedDesign.inspectorWidth : 0
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

    private func sortedAlarms() -> [SchedAlarm] {
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

        var existingCards: [UUID: SchedAlarmCard] = [:]
        for case let card as SchedAlarmCard in cardStack.arrangedSubviews {
            existingCards[card.alarmID] = card
        }
        cardStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let alarms = sortedAlarms()
        listEmpty.isHidden = !alarms.isEmpty
        listHeightConstraint?.constant = min(320, max(100, CGFloat(alarms.count * 84 + 8)))

        for alarm in alarms {
            let card: SchedAlarmCard
            if let reused = existingCards[alarm.id] {
                card = reused
                card.refresh(alarm: alarm, selected: alarm.id == selectedID)
            } else {
                card = SchedAlarmCard(alarm: alarm, selected: alarm.id == selectedID)
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
        for case let card as SchedAlarmCard in cardStack.arrangedSubviews {
            card.setSelected(card.alarmID == selectedID)
        }
    }

    func alarmCardSelected(_ id: UUID) {
        selectedID = selectedID == id ? nil : id
        updateSelectionHighlight()
        reloadInspector()
    }

    func alarmCardEdit(_ id: UUID) {
        selectedID = id
        updateSelectionHighlight()
        reloadInspector()
    }

    func alarmCardMoveLater(_ id: UUID, minutes: Int) {
        guard var alarm = ScheduleStore.shared.store.alarms.first(where: { $0.id == id }) else { return }
        alarm.fireAt = alarm.fireAt.addingTimeInterval(TimeInterval(minutes * 60))
        ScheduleStore.shared.upsert(alarm)
    }

    func alarmCardDuplicate(_ id: UUID) {
        guard var alarm = ScheduleStore.shared.store.alarms.first(where: { $0.id == id }) else { return }
        alarm.id = UUID()
        alarm.title = SchedTextLimits.clean("\(alarm.title) copy", limit: SchedTextLimits.title)
        alarm.enabled = true
        alarm.pausedRemainingSeconds = nil
        selectedID = alarm.id
        ScheduleStore.shared.upsert(alarm)
    }

    func alarmCardDisable(_ id: UUID) {
        guard var alarm = ScheduleStore.shared.store.alarms.first(where: { $0.id == id }) else { return }
        alarm.enabled = false
        if selectedID == id { selectedID = nil }
        AlarmAudioService.shared.stop(alarmID: id)
        InterventionManager.shared.dismiss(alarmID: id)
        ScheduleStore.shared.upsert(alarm)
    }

    func alarmCardDelete(_ id: UUID) {
        if selectedID == id { selectedID = nil }
        AlarmAudioService.shared.stop(alarmID: id)
        InterventionManager.shared.dismiss(alarmID: id)
        ScheduleStore.shared.remove(id: id)
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
        reloadSoundChoices(selected: alarm.sound)
        repeatCheck.state = alarm.repeatDaily ? .on : .off
        enabledCheck.state = alarm.enabled ? .on : .off
        actionPopup.selectItem(at: SchedActionKind.userFacingCases.firstIndex(of: alarm.action.kind) ?? 0)
        actionField.stringValue = alarm.action.payload
        updateActionFieldLabel()
        if alarm.action.kind == .quitApp {
            RunningApps.populate(actionAppPopup, selectedBundleId: nil, selectedName: alarm.action.payload)
        }
        isLoadingInspector = false
    }

    private func reloadSoundChoices(selected: AlarmSound?) {
        soundPopup.removeAllItems()
        soundPopup.addItem(withTitle: "Default · \(ScheduleStore.shared.store.defaultSound.displayName)")
        soundPopup.lastItem?.representedObject = nil
        soundPopup.addItem(withTitle: "None")
        soundPopup.lastItem?.representedObject = AlarmSound.none
        soundPopup.menu?.addItem(.separator())

        if let selected, case .externalFile = selected {
            soundPopup.addItem(withTitle: "Linked · \(selected.displayName)")
            soundPopup.lastItem?.representedObject = selected
            soundPopup.menu?.addItem(.separator())
        }

        for sound in AlarmAudioService.shared.availableSystemSounds() {
            soundPopup.addItem(withTitle: sound.displayName)
            soundPopup.lastItem?.representedObject = sound
        }
        let imported = AlarmAudioService.shared.availableImportedSounds()
        if !imported.isEmpty {
            soundPopup.menu?.addItem(.separator())
            for sound in imported {
                soundPopup.addItem(withTitle: "Imported · \(sound.displayName)")
                soundPopup.lastItem?.representedObject = sound
            }
        }

        if let selected, let index = soundPopup.itemArray.firstIndex(where: { ($0.representedObject as? AlarmSound) == selected }) {
            soundPopup.selectItem(at: index)
        } else {
            soundPopup.selectItem(at: 0)
        }
    }

    @objc private func previewInspectorSound() {
        let sound = (soundPopup.selectedItem?.representedObject as? AlarmSound) ?? ScheduleStore.shared.store.defaultSound
        AlarmAudioService.shared.preview(sound)
    }

    @objc private func reloadActionAppsMenu() {
        let name = actionField.stringValue
        RunningApps.populate(actionAppPopup, selectedBundleId: nil, selectedName: name.isEmpty ? nil : name)
    }

    private func actionPayload() -> String {
        let kind = SchedActionKind.userFacingCases[actionPopup.indexOfSelectedItem]
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
        let kind = SchedActionKind.userFacingCases[actionPopup.indexOfSelectedItem]
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
        let cleanTitle = SchedTextLimits.clean(titleField.stringValue, limit: SchedTextLimits.title)
        alarm.title = cleanTitle.isEmpty ? "Alarm" : cleanTitle
        alarm.note = SchedTextLimits.clean(noteField.stringValue, limit: SchedTextLimits.note)
        alarm.fireAt = datePicker.dateValue
        alarm.level = InterventionLevel.allCases[levelPopup.indexOfSelectedItem]
        alarm.sound = soundPopup.selectedItem?.representedObject as? AlarmSound
        alarm.repeatDaily = repeatCheck.state == .on
        alarm.enabled = enabledCheck.state == .on
        alarm.action = SchedAction.from(
            kind: SchedActionKind.userFacingCases[actionPopup.indexOfSelectedItem],
            payload: SchedTextLimits.clean(actionPayload(), limit: SchedTextLimits.action)
        )
        ScheduleStore.shared.upsert(alarm, notifyOnChange: false)
        hero.refresh()
        if let card = cardStack.arrangedSubviews
            .compactMap({ $0 as? SchedAlarmCard })
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
        let alarm = SchedAlarm(title: "New daily", fireAt: fireAt, level: ScheduleStore.shared.store.defaultLevel, repeatDaily: true)
        selectedID = alarm.id
        ScheduleStore.shared.upsert(alarm)
        view.window?.makeFirstResponder(titleField)
    }

    @objc private func addOneShot() {
        let alarm = SchedAlarm(title: "New reminder", fireAt: Date().addingTimeInterval(1800), level: ScheduleStore.shared.store.defaultLevel)
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
