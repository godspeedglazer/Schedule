import AppKit

@MainActor
final class TimerPanelController: NSViewController, NSTextFieldDelegate {
    private let minutesLabel = NSTextField(string: "25")
    private let minutesStepper = NSStepper()
    private let presetSelector = NSSegmentedControl(
        labels: ["5", "15", "25", "50", "90"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let titleGlass = SchedGlassField(placeholder: "Focus block")
    private let noteGlass = SchedGlassField(placeholder: "Optional note")
    private var titleField: NSTextField { titleGlass.field }
    private var noteField: NSTextField { noteGlass.field }
    private let actionPopup = NSPopUpButton()
    private let actionGlass = SchedGlassField(placeholder: "Shortcut name")
    private var actionField: NSTextField { actionGlass.field }
    private let actionAppPopup = schedAppPopup()
    private let refreshActionAppsButton = SchedGhostButton("Refresh", action: #selector(reloadActionAppsMenu), target: nil)
    private let actionPayloadLabel = schedFieldLabel("Shortcut name")
    private let activeTitle = NSTextField(labelWithString: "No timer running")
    private let activeCountdown = NSTextField(labelWithString: "Set one below")
    private let activeMeta = NSTextField(labelWithString: "")
    private let activeControls = NSStackView()
    private var activeTimerID: UUID?
    private var storeObserver: UUID?
    private var clockTimer: Timer?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear

        let title = NSTextField(labelWithString: "Timer")
        title.font = SchedDesign.display(28)
        SchedDesign.label(title)

        let durationGlass = SchedGlassSurface(cornerRadius: 20, tint: NSColor.white.withAlphaComponent(0.2))
        let detailsGlass = SchedGlassSurface(cornerRadius: 20, tint: NSColor.white.withAlphaComponent(0.2))
        let activeGlass = SchedGlassSurface(cornerRadius: 16, tint: SchedDesign.bubbleSelected)

        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .none
        numberFormatter.allowsFloats = false
        numberFormatter.minimum = 1
        numberFormatter.maximum = 480
        minutesLabel.formatter = numberFormatter
        minutesLabel.font = SchedDesign.mono(40)
        minutesLabel.alignment = .right
        minutesLabel.focusRingType = .none
        minutesLabel.target = self
        minutesLabel.action = #selector(minutesFieldChanged)
        minutesLabel.delegate = self
        minutesLabel.translatesAutoresizingMaskIntoConstraints = false
        minutesLabel.widthAnchor.constraint(equalToConstant: 112).isActive = true
        minutesLabel.heightAnchor.constraint(equalToConstant: 58).isActive = true
        SchedDesign.label(minutesLabel, color: SchedDesign.accent)
        minutesLabel.isEditable = true
        minutesLabel.isSelectable = true
        minutesLabel.isBezeled = true
        minutesLabel.isBordered = true
        minutesLabel.drawsBackground = true
        minutesLabel.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65)
        minutesStepper.minValue = 1
        minutesStepper.maxValue = 480
        minutesStepper.integerValue = 25
        minutesStepper.target = self
        minutesStepper.action = #selector(tick)
        minutesStepper.controlSize = .large

        presetSelector.target = self
        presetSelector.action = #selector(presetChanged)
        presetSelector.selectedSegment = 2
        schedStyleSelector(presetSelector)

        let minCaption = NSTextField(labelWithString: "MINUTES")
        minCaption.font = SchedDesign.section(11)
        SchedDesign.label(minCaption, color: SchedDesign.inkMuted)

        actionPopup.removeAllItems()
        for kind in SchedActionKind.userFacingCases {
            actionPopup.addItem(withTitle: kind.displayName)
        }
        actionPopup.target = self
        actionPopup.action = #selector(actionKindChanged)
        schedStyleSelector(actionPopup)
        schedStyleSelector(actionAppPopup)
        refreshActionAppsButton.target = self
        actionAppPopup.isHidden = true
        refreshActionAppsButton.isHidden = true
        updateActionFieldLabel()

        activeTitle.font = SchedDesign.title(15)
        SchedDesign.label(activeTitle)
        activeCountdown.font = SchedDesign.mono(20)
        SchedDesign.label(activeCountdown, color: SchedDesign.accent)
        activeMeta.font = SchedDesign.caption(11)
        SchedDesign.label(activeMeta, color: SchedDesign.inkMuted)
        activeControls.orientation = .horizontal
        activeControls.alignment = .centerY
        activeControls.spacing = 8
        let activeText = NSStackView(views: [activeTitle, activeCountdown, activeMeta])
        activeText.orientation = .vertical
        activeText.alignment = .leading
        activeText.spacing = 2
        let activeSpacer = NSView()
        activeSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let activeRow = NSStackView(views: [activeText, activeSpacer, activeControls])
        activeRow.orientation = .horizontal
        activeRow.alignment = .centerY
        activeRow.spacing = 12
        activeRow.translatesAutoresizingMaskIntoConstraints = false
        activeGlass.innerContentView.addSubview(activeRow)
        NSLayoutConstraint.activate([
            activeRow.leadingAnchor.constraint(equalTo: activeGlass.innerContentView.leadingAnchor, constant: 18),
            activeRow.trailingAnchor.constraint(equalTo: activeGlass.innerContentView.trailingAnchor, constant: -18),
            activeRow.topAnchor.constraint(equalTo: activeGlass.innerContentView.topAnchor, constant: 14),
            activeRow.bottomAnchor.constraint(equalTo: activeGlass.innerContentView.bottomAnchor, constant: -14),
        ])

        let start = SchedPrimaryButton("Start timer", action: #selector(start), target: self)
        start.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true

        let minuteRow = NSStackView(views: [minutesLabel, minutesStepper])
        minuteRow.orientation = .horizontal
        minuteRow.alignment = .centerY
        minuteRow.spacing = 12

        let durationStack = NSStackView(views: [
            minCaption, minuteRow, schedFieldLabel("Quick duration"), presetSelector,
        ])
        durationStack.orientation = .vertical
        durationStack.alignment = .leading
        durationStack.spacing = 12
        durationStack.translatesAutoresizingMaskIntoConstraints = false

        let actionSpacer = NSView()
        actionSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let actionRow = NSStackView(views: [actionSpacer, start])
        actionRow.orientation = .horizontal
        actionRow.alignment = .centerY

        let detailsStack = NSStackView()
        detailsStack.orientation = .vertical
        detailsStack.alignment = .leading
        detailsStack.spacing = 10
        detailsStack.translatesAutoresizingMaskIntoConstraints = false
        [schedFieldLabel("Title"), titleGlass,
         schedFieldLabel("Note"), noteGlass,
         schedFieldLabel("Then run"), actionPopup,
         actionPayloadLabel, actionGlass, actionAppPopup, refreshActionAppsButton,
         actionRow].forEach { detailsStack.addArrangedSubview($0) }
        titleField.stringValue = "Focus block"

        durationGlass.innerContentView.addSubview(durationStack)
        detailsGlass.innerContentView.addSubview(detailsStack)
        view.addSubview(title)
        view.addSubview(activeGlass)
        view.addSubview(durationGlass)
        view.addSubview(detailsGlass)
        title.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            activeGlass.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            activeGlass.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            activeGlass.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            activeGlass.heightAnchor.constraint(equalToConstant: 82),
            durationGlass.topAnchor.constraint(equalTo: activeGlass.bottomAnchor, constant: 14),
            durationGlass.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            durationGlass.widthAnchor.constraint(equalToConstant: 240),
            durationGlass.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),
            detailsGlass.topAnchor.constraint(equalTo: durationGlass.topAnchor),
            detailsGlass.leadingAnchor.constraint(equalTo: durationGlass.trailingAnchor, constant: 16),
            detailsGlass.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            detailsGlass.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor),

            durationStack.topAnchor.constraint(equalTo: durationGlass.innerContentView.topAnchor, constant: 24),
            durationStack.leadingAnchor.constraint(equalTo: durationGlass.innerContentView.leadingAnchor, constant: 24),
            durationStack.trailingAnchor.constraint(equalTo: durationGlass.innerContentView.trailingAnchor, constant: -24),
            durationStack.bottomAnchor.constraint(equalTo: durationGlass.innerContentView.bottomAnchor, constant: -24),
            presetSelector.widthAnchor.constraint(equalTo: durationStack.widthAnchor),

            detailsStack.topAnchor.constraint(equalTo: detailsGlass.innerContentView.topAnchor, constant: 24),
            detailsStack.leadingAnchor.constraint(equalTo: detailsGlass.innerContentView.leadingAnchor, constant: 24),
            detailsStack.trailingAnchor.constraint(equalTo: detailsGlass.innerContentView.trailingAnchor, constant: -24),
            detailsStack.bottomAnchor.constraint(equalTo: detailsGlass.innerContentView.bottomAnchor, constant: -24),
            titleGlass.widthAnchor.constraint(equalTo: detailsStack.widthAnchor),
            noteGlass.widthAnchor.constraint(equalTo: detailsStack.widthAnchor),
            actionPopup.widthAnchor.constraint(equalTo: detailsStack.widthAnchor),
            actionGlass.widthAnchor.constraint(equalTo: detailsStack.widthAnchor),
            actionAppPopup.widthAnchor.constraint(equalTo: detailsStack.widthAnchor),
            actionRow.widthAnchor.constraint(equalTo: detailsStack.widthAnchor),
        ])
        reloadActiveTimer()
        startLiveUpdates()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        reloadActionAppsMenu()
        reloadActiveTimer()
    }

    private func startLiveUpdates() {
        if storeObserver == nil {
            storeObserver = ScheduleStore.shared.observeChanges { [weak self] in self?.reloadActiveTimer() }
        }
        clockTimer?.invalidate()
        clockTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateActiveCountdown() }
        }
        if let clockTimer { RunLoop.main.add(clockTimer, forMode: .common) }
    }

    @objc private func reloadActionAppsMenu() {
        RunningApps.populate(actionAppPopup, selectedBundleId: nil, selectedName: nil)
    }

    private func actionPayload() -> String {
        let kind = SchedActionKind.userFacingCases[actionPopup.indexOfSelectedItem]
        if kind == .quitApp, let app = RunningApps.selectedApp(from: actionAppPopup) {
            return app.name
        }
        return actionField.stringValue
    }

    @objc private func actionKindChanged() { updateActionFieldLabel() }

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

    @objc private func tick() {
        minutesLabel.integerValue = minutesStepper.integerValue
        syncPresetSelection()
    }
    @objc private func minutesFieldChanged() {
        minutesStepper.integerValue = max(1, min(480, minutesLabel.integerValue))
        tick()
    }
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === minutesLabel,
              let value = Int(field.stringValue) else { return }
        minutesStepper.integerValue = max(1, min(480, value))
        syncPresetSelection()
    }
    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === minutesLabel else { return }
        minutesFieldChanged()
    }
    @objc private func presetChanged() {
        let values = [5, 15, 25, 50, 90]
        guard presetSelector.selectedSegment >= 0 else { return }
        minutesStepper.integerValue = values[presetSelector.selectedSegment]
        tick()
    }

    private func syncPresetSelection() {
        let values = [5, 15, 25, 50, 90]
        presetSelector.selectedSegment = values.firstIndex(of: minutesStepper.integerValue) ?? -1
    }

    @objc private func start() {
        let action = SchedAction.from(
            kind: SchedActionKind.userFacingCases[actionPopup.indexOfSelectedItem],
            payload: actionPayload()
        )
        _ = TimerService.shared.start(
            minutes: max(1, min(480, minutesLabel.integerValue)),
            title: titleField.stringValue.isEmpty ? "Timer" : titleField.stringValue,
            note: noteField.stringValue.isEmpty ? "Timer complete. Take a breath before the next thing." : noteField.stringValue,
            level: .gentle,
            action: action
        )
        reloadActiveTimer()
    }

    private func reloadActiveTimer() {
        guard let snapshot = TimerService.shared.snapshot() else {
            activeTimerID = nil
            activeTitle.stringValue = "No timer running"
            activeCountdown.stringValue = "Set one below"
            activeMeta.stringValue = ""
            activeControls.arrangedSubviews.forEach { $0.removeFromSuperview() }
            return
        }
        activeTimerID = snapshot.id
        let timerCount = TimerService.shared.activeTimers().count
        activeTitle.stringValue = timerCount == 1 ? snapshot.title : "\(snapshot.title) · +\(timerCount - 1) more"
        activeControls.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let pauseTitle = snapshot.isPaused ? "Resume" : "Pause"
        let pause = SchedGhostButton(pauseTitle, action: #selector(pauseOrResume), target: self)
        let add = SchedGhostButton("+5m", action: #selector(addFiveMinutes), target: self)
        let floating = SchedGhostButton("Float", action: #selector(showFloatingTimer), target: self)
        let cancel = SchedDangerButton("Cancel", action: #selector(cancelTimer), target: self)
        [pause, add, floating, cancel].forEach { activeControls.addArrangedSubview($0) }
        updateActiveCountdown()
    }

    private func updateActiveCountdown() {
        guard let snapshot = TimerService.shared.snapshot(), snapshot.id == activeTimerID else {
            reloadActiveTimer()
            return
        }
        activeCountdown.stringValue = snapshot.formattedRemaining
        if snapshot.isPaused {
            activeMeta.stringValue = "Paused"
        } else {
            activeMeta.stringValue = "Ends \(SchedTimeFormat.string(from: snapshot.fireAt))"
        }
    }

    @objc private func pauseOrResume() {
        TimerService.shared.pauseOrResume(id: activeTimerID)
        reloadActiveTimer()
    }

    @objc private func addFiveMinutes() {
        TimerService.shared.add(minutes: 5, id: activeTimerID)
        updateActiveCountdown()
    }

    @objc private func showFloatingTimer() {
        FloatingTimerController.shared.show()
    }

    @objc private func cancelTimer() {
        TimerService.shared.cancel(id: activeTimerID)
        reloadActiveTimer()
    }

}
