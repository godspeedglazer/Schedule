import AppKit

@MainActor
final class FloatingTimerController: NSWindowController, NSWindowDelegate {
    static let shared = FloatingTimerController()

    private let titleLabel = NSTextField(labelWithString: "Focus")
    private let countdownLabel = NSTextField(labelWithString: "25:00")
    private let pauseButton = SchedGhostButton("Pause", action: #selector(pauseOrResume), target: nil)
    private let addButton = SchedGhostButton("+5m", action: #selector(addFive), target: nil)
    private let finishButton = SchedPrimaryButton("Finish", action: #selector(finish), target: nil)
    private var tickTimer: Timer?
    private var timerObserver: UUID?
    private var storeObserver: UUID?
    private var hasStartedObserving = false

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 126),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Timer"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = NSSize(width: 270, height: 118)
        panel.maxSize = NSSize(width: 420, height: 180)
        _ = panel.setFrameAutosaveName("Sched.FloatingTimer")

        super.init(window: panel)
        panel.delegate = self
        buildContent()
        refreshWindowLevel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func startObserving() {
        guard !hasStartedObserving else { return }
        hasStartedObserving = true
        timerObserver = TimerService.shared.observeChanges { [weak self] in
            self?.timerStateChanged()
        }
        storeObserver = ScheduleStore.shared.observeChanges { [weak self] in
            self?.preferencesChanged()
        }
    }

    func show() {
        startObserving()
        guard TimerService.shared.snapshot() != nil else {
            MainWindowController.shared.showSection(.timer)
            MainWindowController.shared.showWindow()
            return
        }
        refresh()
        refreshWindowLevel()
        if window?.frame.origin == .zero {
            window?.center()
        }
        window?.orderFrontRegardless()
        startTicks()
    }

    func hide() {
        tickTimer?.invalidate()
        tickTimer = nil
        window?.orderOut(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    private func buildContent() {
        guard let window else { return }
        let root = SchedGlassSurface(cornerRadius: 18, tint: NSColor.windowBackgroundColor.withAlphaComponent(0.34))
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = root

        titleLabel.font = SchedDesign.title(14)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        SchedDesign.label(titleLabel)

        countdownLabel.font = SchedDesign.mono(32)
        countdownLabel.alignment = .right
        countdownLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        SchedDesign.label(countdownLabel, color: SchedDesign.accent)

        pauseButton.target = self
        addButton.target = self
        finishButton.target = self

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let top = NSStackView(views: [titleLabel, spacer, countdownLabel])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 12

        let controls = NSStackView(views: [pauseButton, addButton, finishButton])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8

        let stack = NSStackView(views: [top, controls])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.innerContentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.innerContentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: root.innerContentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: root.innerContentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: root.innerContentView.bottomAnchor, constant: -14),
            top.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    private func timerStateChanged() {
        refresh()
        let preferences = ScheduleStore.shared.store
        if let _ = TimerService.shared.snapshot() {
            if preferences.floatingTimerAutoShow { show() }
        } else {
            hide()
        }
    }

    private func preferencesChanged() {
        refreshWindowLevel()
        if !ScheduleStore.shared.store.floatingTimerAutoShow, window?.isVisible != true {
            tickTimer?.invalidate()
            tickTimer = nil
        }
        refresh()
    }

    private func refreshWindowLevel() {
        window?.level = ScheduleStore.shared.store.floatingTimerAlwaysOnTop ? .floating : .normal
    }

    private func startTicks() {
        guard tickTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        tickTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refresh() {
        guard let snapshot = TimerService.shared.snapshot() else {
            titleLabel.stringValue = "No timer running"
            countdownLabel.stringValue = "00:00"
            pauseButton.isEnabled = false
            addButton.isEnabled = false
            finishButton.isEnabled = false
            return
        }
        titleLabel.stringValue = snapshot.title
        titleLabel.toolTip = snapshot.note.isEmpty ? snapshot.title : "\(snapshot.title)\n\(snapshot.note)"
        countdownLabel.stringValue = snapshot.formattedRemaining
        pauseButton.title = snapshot.isPaused ? "Resume" : "Pause"
        pauseButton.isEnabled = true
        addButton.isEnabled = true
        finishButton.isEnabled = true
    }

    @objc private func pauseOrResume() {
        TimerService.shared.pauseOrResume()
        refresh()
    }

    @objc private func addFive() {
        TimerService.shared.add(minutes: 5)
        refresh()
    }

    @objc private func finish() {
        TimerService.shared.finish()
        hide()
    }
}
