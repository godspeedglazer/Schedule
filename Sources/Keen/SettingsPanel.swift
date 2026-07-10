import AppKit
import ServiceManagement

@MainActor
final class SettingsPanelController: NSViewController, NSTextFieldDelegate {
    private let scroll = NSScrollView()
    private let defaultLevel = NSPopUpButton()
    private let snoozeField = SettingsPanelController.integerField(value: 5, maximum: 60)
    private let snoozeStepper = NSStepper()
    private let idleField = SettingsPanelController.integerField(value: 0, maximum: 240)
    private let idleStepper = NSStepper()

    private let launchCheck = NSButton(checkboxWithTitle: "Open at login", target: nil, action: nil)
    private let headlessCheck = NSButton(checkboxWithTitle: "Keep reminders running when the window is closed", target: nil, action: nil)
    private let soundCheck = NSButton(checkboxWithTitle: "Play a sound", target: nil, action: nil)
    private let repeatSoundCheck = NSButton(checkboxWithTitle: "Repeat sound until handled", target: nil, action: nil)
    private let notificationsCheck = NSButton(checkboxWithTitle: "Also use macOS notifications", target: nil, action: nil)
    private let notificationStatus = NSTextField(labelWithString: "Checking notification access…")

    private let menuIconCheck = NSButton(checkboxWithTitle: "Icon", target: nil, action: nil)
    private let menuDateCheck = NSButton(checkboxWithTitle: "Date", target: nil, action: nil)
    private let menuTimeCheck = NSButton(checkboxWithTitle: "Time", target: nil, action: nil)
    private let menuSecondsCheck = NSButton(checkboxWithTitle: "Seconds", target: nil, action: nil)
    private let menuCountdownCheck = NSButton(checkboxWithTitle: "Next reminder countdown", target: nil, action: nil)
    private let hourStylePopup = NSPopUpButton()
    private let periodCheck = NSButton(checkboxWithTitle: "Show AM/PM", target: nil, action: nil)

    private let targetPopup = keenAppPopup()
    private var chosenTarget: RunningApp?
    private let limitField = SettingsPanelController.integerField(value: 45, maximum: 480)
    private let limitStepper = NSStepper()
    private let limitsList = NSStackView()

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear

        let title = NSTextField(labelWithString: "Preferences")
        title.font = KeenDesign.display(28)
        KeenDesign.label(title)

        let document = KeenFlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        schedConfigureScroll(scroll)
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 24, right: 0)

        configureControls()

        let general = card(stack: generalStack())
        let menuBar = card(stack: menuBarStack())
        let limits = card(stack: limitsStack())
        let content = NSStackView(views: [
            sectionTitle("General"), general,
            sectionTitle("Menu bar"), menuBar,
            sectionTitle("App limits"), limits,
        ])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 10
        content.setCustomSpacing(24, after: general)
        content.setCustomSpacing(24, after: menuBar)
        content.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)

        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: document.topAnchor),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24),
            general.widthAnchor.constraint(equalTo: content.widthAnchor),
            menuBar.widthAnchor.constraint(equalTo: content.widthAnchor),
            limits.widthAnchor.constraint(equalTo: content.widthAnchor),
        ])

        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.widthAnchor.constraint(equalTo: clip.widthAnchor),
        ])

        view.addSubview(title)
        view.addSubview(scroll)
        title.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        reload()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        reloadTargets()
        refreshNotificationHealth()
        view.layoutSubtreeIfNeeded()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scroll.contentView.scroll(to: .zero)
            self.scroll.reflectScrolledClipView(self.scroll.contentView)
        }
    }

    private func configureControls() {
        defaultLevel.removeAllItems()
        InterventionLevel.allCases.forEach { defaultLevel.addItem(withTitle: $0.label) }
        schedStyleSelector(defaultLevel)
        defaultLevel.target = self
        defaultLevel.action = #selector(save)

        configure(stepper: snoozeStepper, minimum: 1, maximum: 60, action: #selector(generalStepperChanged(_:)))
        configure(stepper: idleStepper, minimum: 0, maximum: 240, action: #selector(generalStepperChanged(_:)))
        configure(stepper: limitStepper, minimum: 1, maximum: 480, action: #selector(limitStepperChanged(_:)))
        snoozeField.target = self; snoozeField.action = #selector(generalFieldChanged(_:))
        idleField.target = self; idleField.action = #selector(generalFieldChanged(_:))
        limitField.target = self; limitField.action = #selector(limitFieldChanged(_:))
        snoozeField.delegate = self
        idleField.delegate = self
        limitField.delegate = self

        for check in [launchCheck, headlessCheck, soundCheck, repeatSoundCheck, notificationsCheck,
                      menuIconCheck, menuDateCheck, menuTimeCheck, menuSecondsCheck, menuCountdownCheck] {
            check.target = self
            check.action = #selector(save)
        }

        schedStyleSelector(targetPopup)
        targetPopup.target = self
        targetPopup.action = #selector(targetChanged)
        limitsList.orientation = .vertical
        limitsList.alignment = .leading
        limitsList.spacing = 8

        hourStylePopup.removeAllItems()
        HourStyle.allCases.forEach { hourStylePopup.addItem(withTitle: $0.label) }
        schedStyleSelector(hourStylePopup)
        hourStylePopup.target = self
        hourStylePopup.action = #selector(save)
        periodCheck.target = self
        periodCheck.action = #selector(save)
    }

    private func generalStack() -> NSStackView {
        let stack = verticalStack()
        stack.addArrangedSubview(formRow("Default alert", control: defaultLevel))
        stack.addArrangedSubview(formRow("Default snooze", control: numberEditor(snoozeField, snoozeStepper, suffix: "minutes")))
        stack.addArrangedSubview(formRow("Idle reminder", control: numberEditor(idleField, idleStepper, suffix: "minutes · 0 is off")))
        for check in [launchCheck, headlessCheck, soundCheck, repeatSoundCheck, notificationsCheck] {
            stack.addArrangedSubview(check)
        }
        let testNotification = KeenGhostButton("Test sound + notification", action: #selector(testNotification), target: self)
        notificationStatus.font = KeenDesign.caption(11)
        KeenDesign.label(notificationStatus, color: KeenDesign.inkMuted)
        stack.addArrangedSubview(testNotification)
        stack.addArrangedSubview(notificationStatus)
        defaultLevel.widthAnchor.constraint(equalToConstant: 300).isActive = true
        return stack
    }

    @objc private func testNotification() {
        NotificationService.shared.deliverTest()
        refreshNotificationHealth()
    }

    private func refreshNotificationHealth() {
        NotificationService.shared.notificationHealth { [weak self] message, ready in
            guard let self else { return }
            self.notificationStatus.stringValue = message
            self.notificationStatus.textColor = ready ? .systemGreen : KeenDesign.accent
        }
    }

    private func menuBarStack() -> NSStackView {
        let stack = verticalStack()
        let intro = helper("Choose only what earns space in the menu bar. The calendar remains available from the menu.")
        let components = NSStackView(views: [menuIconCheck, menuDateCheck, menuTimeCheck, menuSecondsCheck])
        components.orientation = .horizontal
        components.spacing = 16
        stack.addArrangedSubview(intro)
        stack.addArrangedSubview(formRow("Show", control: components))
        stack.addArrangedSubview(formRow("Clock", control: hourStylePopup))
        stack.addArrangedSubview(periodCheck)
        stack.addArrangedSubview(menuCountdownCheck)
        hourStylePopup.widthAnchor.constraint(equalToConstant: 180).isActive = true
        return stack
    }

    private func limitsStack() -> NSStackView {
        let stack = verticalStack()
        stack.addArrangedSubview(helper("Choose any installed app—or an executable—and decide when Sched should intervene."))
        stack.addArrangedSubview(formRow("App or executable", control: targetPopup))
        stack.addArrangedSubview(formRow("Remind me after", control: numberEditor(limitField, limitStepper, suffix: "minutes open")))
        let add = KeenPrimaryButton("Add limit", action: #selector(addLimit), target: self)
        stack.addArrangedSubview(add)
        stack.setCustomSpacing(16, after: add)
        stack.addArrangedSubview(keenFieldLabel("Active limits"))
        stack.addArrangedSubview(limitsList)
        targetPopup.widthAnchor.constraint(equalToConstant: 360).isActive = true
        return stack
    }

    private func reload() {
        let s = ScheduleStore.shared.store
        defaultLevel.selectItem(at: InterventionLevel.allCases.firstIndex(of: s.defaultLevel) ?? 0)
        snoozeField.integerValue = s.snoozeMinutes
        snoozeStepper.integerValue = s.snoozeMinutes
        let idle = s.idleMinutesBeforeNudge ?? 0
        idleField.integerValue = idle
        idleStepper.integerValue = idle
        launchCheck.state = s.launchAtLogin ? .on : .off
        headlessCheck.state = s.headlessWhenClosed ? .on : .off
        soundCheck.state = s.playSoundOnAlert ? .on : .off
        repeatSoundCheck.state = s.repeatSoundOnAlert ? .on : .off
        repeatSoundCheck.isEnabled = s.playSoundOnAlert
        notificationsCheck.state = s.systemNotificationsEnabled ? .on : .off
        menuIconCheck.state = s.menuBarShowIcon ? .on : .off
        menuDateCheck.state = s.menuBarShowDate ? .on : .off
        menuTimeCheck.state = s.menuBarShowTime ? .on : .off
        menuSecondsCheck.state = s.menuBarShowSeconds ? .on : .off
        menuSecondsCheck.isEnabled = s.menuBarShowTime
        menuCountdownCheck.state = s.menuBarShowNextCountdown ? .on : .off
        hourStylePopup.selectItem(at: HourStyle.allCases.firstIndex(of: s.hourStyle) ?? 0)
        periodCheck.state = s.showAMPM ? .on : .off
        periodCheck.isEnabled = !SchedTimeFormat.resolvedUses24Hour(s.hourStyle)
        reloadLimits()
    }

    private func reloadTargets() {
        RunningApps.populate(targetPopup, selectedBundleId: chosenTarget?.bundleId, selectedName: chosenTarget?.name)
        if let chosenTarget,
           !targetPopup.itemArray.contains(where: {
               guard let values = $0.representedObject as? [String: String] else { return false }
               return values["bundleId"] == (chosenTarget.bundleId ?? "")
                   && values["executablePath"] == (chosenTarget.executablePath ?? "")
           }) {
            targetPopup.addItem(withTitle: chosenTarget.name)
            targetPopup.lastItem?.representedObject = [
                "name": chosenTarget.name,
                "bundleId": chosenTarget.bundleId ?? "",
                "executablePath": chosenTarget.executablePath ?? "",
            ]
            targetPopup.lastItem?.image = chosenTarget.icon
            targetPopup.lastItem?.image?.size = NSSize(width: 16, height: 16)
            targetPopup.select(targetPopup.lastItem)
        }
        targetPopup.menu?.addItem(.separator())
        let choose = NSMenuItem(title: "Choose Other…", action: nil, keyEquivalent: "")
        choose.representedObject = ["picker": "true"]
        targetPopup.menu?.addItem(choose)
        if chosenTarget == nil { chosenTarget = RunningApps.selectedApp(from: targetPopup) }
    }

    private func reloadLimits() {
        limitsList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let watches = ScheduleStore.shared.store.appWatches
        guard !watches.isEmpty else {
            limitsList.addArrangedSubview(helper("No app limits yet."))
            return
        }
        for watch in watches {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 8

            let icon = NSImageView()
            icon.image = RunningApps.availableTargets().first(where: {
                ($0.bundleId != nil && $0.bundleId == watch.bundleId) || $0.executablePath == watch.executablePath
            })?.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.widthAnchor.constraint(equalToConstant: 18).isActive = true
            icon.heightAnchor.constraint(equalToConstant: 18).isActive = true

            let name = NSTextField(labelWithString: watch.appName)
            name.font = KeenDesign.body(13)
            name.lineBreakMode = .byTruncatingTail
            name.widthAnchor.constraint(equalToConstant: 170).isActive = true

            let minutes = Self.integerField(value: watch.maxMinutes, maximum: 480)
            minutes.identifier = NSUserInterfaceItemIdentifier(watch.id.uuidString)
            minutes.target = self
            minutes.action = #selector(editLimitMinutes(_:))
            minutes.delegate = self
            let stepper = NSStepper()
            configure(stepper: stepper, minimum: 1, maximum: 480, action: #selector(editLimitMinutes(_:)))
            stepper.integerValue = watch.maxMinutes
            stepper.identifier = minutes.identifier

            let suffix = NSTextField(labelWithString: "min")
            suffix.textColor = KeenDesign.inkMuted
            let enabled = NSButton(checkboxWithTitle: "Active", target: self, action: #selector(toggleLimit(_:)))
            enabled.state = watch.enabled ? .on : .off
            enabled.identifier = minutes.identifier
            let remove = KeenGhostButton("Remove", action: #selector(removeLimit(_:)), target: self)
            remove.identifier = minutes.identifier

            [icon, name, minutes, stepper, suffix, enabled, remove].forEach { row.addArrangedSubview($0) }
            limitsList.addArrangedSubview(row)
        }
    }

    @objc private func save() {
        var s = ScheduleStore.shared.store
        if ![menuIconCheck, menuDateCheck, menuTimeCheck].contains(where: { $0.state == .on }) {
            menuIconCheck.state = .on
        }
        s.defaultLevel = InterventionLevel.allCases[max(0, defaultLevel.indexOfSelectedItem)]
        s.snoozeMinutes = clamped(snoozeField.integerValue, 1...60)
        let idle = clamped(idleField.integerValue, 0...240)
        s.idleMinutesBeforeNudge = idle == 0 ? nil : idle
        s.launchAtLogin = launchCheck.state == .on
        s.headlessWhenClosed = headlessCheck.state == .on
        s.playSoundOnAlert = soundCheck.state == .on
        s.repeatSoundOnAlert = repeatSoundCheck.state == .on
        s.systemNotificationsEnabled = notificationsCheck.state == .on
        s.menuBarShowIcon = menuIconCheck.state == .on
        s.menuBarShowDate = menuDateCheck.state == .on
        s.menuBarShowTime = menuTimeCheck.state == .on
        s.menuBarShowSeconds = menuSecondsCheck.state == .on && s.menuBarShowTime
        s.menuBarShowNextCountdown = menuCountdownCheck.state == .on
        s.hourStyle = HourStyle.allCases[max(0, hourStylePopup.indexOfSelectedItem)]
        s.showAMPM = periodCheck.state == .on
        repeatSoundCheck.isEnabled = s.playSoundOnAlert
        menuSecondsCheck.isEnabled = s.menuBarShowTime
        if !s.menuBarShowTime { menuSecondsCheck.state = .off }
        periodCheck.isEnabled = !SchedTimeFormat.resolvedUses24Hour(s.hourStyle)
        ScheduleStore.shared.replaceStore(s)
        if s.systemNotificationsEnabled { NotificationService.shared.requestAuthorizationIfNeeded() }
        LoginItemHelper.sync(enabled: s.launchAtLogin)
        AccessibilityMonitor.shared.start()
    }

    @objc private func generalStepperChanged(_ sender: NSStepper) {
        if sender === snoozeStepper { snoozeField.integerValue = sender.integerValue }
        if sender === idleStepper { idleField.integerValue = sender.integerValue }
        save()
    }

    @objc private func generalFieldChanged(_ sender: NSTextField) {
        if sender === snoozeField { snoozeStepper.integerValue = clamped(sender.integerValue, 1...60) }
        if sender === idleField { idleStepper.integerValue = clamped(sender.integerValue, 0...240) }
        save()
    }

    @objc private func limitStepperChanged(_ sender: NSStepper) {
        limitField.integerValue = sender.integerValue
    }

    @objc private func limitFieldChanged(_ sender: NSTextField) {
        limitStepper.integerValue = clamped(sender.integerValue, 1...480)
        sender.integerValue = limitStepper.integerValue
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        if field === snoozeField || field === idleField {
            generalFieldChanged(field)
        } else if field === limitField {
            limitFieldChanged(field)
        } else if field.identifier != nil {
            editLimitMinutes(field)
        }
    }

    @objc private func targetChanged() {
        if let values = targetPopup.selectedItem?.representedObject as? [String: String], values["picker"] == "true" {
            chooseOtherTarget()
        } else {
            chosenTarget = RunningApps.selectedApp(from: targetPopup)
        }
    }

    private func chooseOtherTarget() {
        let panel = NSOpenPanel()
        panel.title = "Choose an App or Executable"
        panel.message = "Select an application bundle or executable file."
        panel.prompt = "Choose"
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url, let target = RunningApps.target(for: url) else {
            reloadTargets()
            return
        }
        chosenTarget = target
        reloadTargets()
        if let index = targetPopup.itemArray.firstIndex(where: {
            ($0.representedObject as? [String: String])?["name"] == target.name
        }) { targetPopup.selectItem(at: index) }
    }

    @objc private func addLimit() {
        guard let app = chosenTarget ?? RunningApps.selectedApp(from: targetPopup) else { return }
        var s = ScheduleStore.shared.store
        guard !s.appWatches.contains(where: {
            if let bundleId = app.bundleId, !bundleId.isEmpty { return $0.bundleId == bundleId }
            return $0.executablePath == app.executablePath
        }) else { NSSound.beep(); return }
        s.appWatches.append(KeenAppWatch(
            appName: app.name,
            bundleId: app.bundleId,
            executablePath: app.executablePath,
            maxMinutes: clamped(limitField.integerValue, 1...480),
            level: s.defaultLevel,
            action: .quitApp(name: app.name)
        ))
        ScheduleStore.shared.replaceStore(s)
        reloadLimits()
    }

    @objc private func editLimitMinutes(_ sender: NSControl) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        var s = ScheduleStore.shared.store
        guard let index = s.appWatches.firstIndex(where: { $0.id == id }) else { return }
        let value = clamped(sender.integerValue, 1...480)
        sender.integerValue = value
        s.appWatches[index].maxMinutes = value
        ScheduleStore.shared.replaceStore(s)
        if let row = sender.superview as? NSStackView {
            for case let peer as NSControl in row.arrangedSubviews
                where peer.identifier == sender.identifier && peer !== sender {
                peer.integerValue = value
            }
        }
    }

    @objc private func toggleLimit(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        var s = ScheduleStore.shared.store
        guard let index = s.appWatches.firstIndex(where: { $0.id == id }) else { return }
        s.appWatches[index].enabled = sender.state == .on
        ScheduleStore.shared.replaceStore(s)
    }

    @objc private func removeLimit(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let id = UUID(uuidString: raw) else { return }
        var s = ScheduleStore.shared.store
        s.appWatches.removeAll { $0.id == id }
        ScheduleStore.shared.replaceStore(s)
        reloadLimits()
    }

    private func card(stack: NSStackView) -> KeenGlassSurface {
        let glass = KeenGlassSurface()
        glass.innerContentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: glass.innerContentView.topAnchor, constant: 20),
            stack.leadingAnchor.constraint(equalTo: glass.innerContentView.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: glass.innerContentView.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: glass.innerContentView.bottomAnchor, constant: -20),
        ])
        return glass
    }

    private func verticalStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func formRow(_ label: String, control: NSView) -> NSStackView {
        let caption = keenFieldLabel(label)
        caption.widthAnchor.constraint(equalToConstant: 140).isActive = true
        let row = NSStackView(views: [caption, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return row
    }

    private func numberEditor(_ field: NSTextField, _ stepper: NSStepper, suffix: String) -> NSStackView {
        let suffixLabel = NSTextField(labelWithString: suffix)
        suffixLabel.font = KeenDesign.body(12)
        suffixLabel.textColor = KeenDesign.inkMuted
        let row = NSStackView(views: [field, stepper, suffixLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        return row
    }

    private func sectionTitle(_ value: String) -> NSTextField {
        let label = NSTextField(labelWithString: value)
        label.font = KeenDesign.title(18)
        KeenDesign.label(label)
        return label
    }

    private func helper(_ value: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: value)
        label.font = KeenDesign.body(12)
        KeenDesign.label(label, color: KeenDesign.inkMuted)
        label.preferredMaxLayoutWidth = 520
        return label
    }

    private func configure(stepper: NSStepper, minimum: Double, maximum: Double, action: Selector) {
        stepper.minValue = minimum
        stepper.maxValue = maximum
        stepper.increment = 1
        stepper.target = self
        stepper.action = action
    }

    private static func integerField(value: Int, maximum: Int) -> NSTextField {
        let field = NSTextField(string: "\(value)")
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.allowsFloats = false
        formatter.minimum = 0
        formatter.maximum = NSNumber(value: maximum)
        field.formatter = formatter
        field.alignment = .right
        field.font = KeenDesign.mono(14)
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 58).isActive = true
        field.heightAnchor.constraint(equalToConstant: 28).isActive = true
        return field
    }

    private func clamped(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(range.upperBound, max(range.lowerBound, value))
    }
}

@MainActor
enum LoginItemHelper {
    static func sync(enabled: Bool) {
        if #available(macOS 13.0, *) {
            try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}
