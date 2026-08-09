import AppKit
import Foundation

@MainActor
final class InterventionWindowController: NSWindowController, NSWindowDelegate {
    private static let gentleOriginKey = "Sched.GentleReminderOrigin"
    private let alarm: SchedAlarm
    var alarmID: UUID { alarm.id }
    private var onDismiss: (() -> Void)?
    private var countdownTimer: Timer?
    private var takeoverSecondsRemaining = 2

    init(alarm: SchedAlarm, onDismiss: @escaping () -> Void) {
        self.alarm = alarm
        self.onDismiss = onDismiss

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let window: NSWindow

        switch alarm.level {
        case .gentle:
            let size = NSSize(width: 440, height: 166)
            let origin = Self.restoredGentleOrigin(size: size, fallbackScreen: screen)
            window = SchedPanel(
                contentRect: NSRect(origin: origin, size: size),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
            window.isMovable = true
            window.isMovableByWindowBackground = true

        case .focus, .takeover:
            window = SchedPanel(
                contentRect: screen.frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = alarm.level == .gentle
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self

        let dismiss: () -> Void = { [weak self] in self?.dismiss(runAction: true) }
        let snooze: (Int) -> Void = { [weak self] minutes in self?.snooze(minutes: minutes) }
        let act: () -> Void = { [weak self] in self?.act() }

        switch alarm.level {
        case .gentle:
            window.contentView = SchedGentleToast(
                title: alarm.title,
                note: alarm.note,
                onDone: dismiss,
                onSnooze: snooze,
                onAction: alarm.action == .none ? nil : act
            )
        case .focus:
            window.contentView = OverlayView(
                alarm: alarm,
                style: .focus,
                dismiss: dismiss,
                snooze: snooze,
                act: act
            )
        case .takeover:
            window.contentView = OverlayView(
                alarm: alarm,
                style: .takeover,
                dismiss: dismiss,
                snooze: snooze,
                act: act,
                onReadyToDismiss: { [weak self] in self?.takeoverView?.enableDismiss() }
            )
        }

        window.orderFrontRegardless()
        window.makeFirstResponder(nil)
        if alarm.level == .takeover {
            startTakeoverCountdown()
        }


        InterventionManager.shared.register(self)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func windowDidMove(_ notification: Notification) {
        guard alarm.level == .gentle, let window else { return }
        UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: Self.gentleOriginKey)
    }

    private static func restoredGentleOrigin(size: NSSize, fallbackScreen: NSScreen) -> NSPoint {
        let fallback = NSPoint(
            x: fallbackScreen.visibleFrame.maxX - size.width - 18,
            y: fallbackScreen.visibleFrame.maxY - size.height - 18
        )
        guard let raw = UserDefaults.standard.string(forKey: gentleOriginKey) else { return fallback }
        let saved = NSPointFromString(raw)
        let savedFrame = NSRect(origin: saved, size: size)
        let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(savedFrame) }) ?? fallbackScreen
        let visible = screen.visibleFrame
        return NSPoint(
            x: min(max(saved.x, visible.minX), visible.maxX - size.width),
            y: min(max(saved.y, visible.minY), visible.maxY - size.height)
        )
    }

    private var takeoverView: TakeoverContent? {
        (window?.contentView as? OverlayView)?.takeoverContent
    }

    func forceDismiss() {
        dismiss(runAction: false)
    }

    private func dismiss(runAction: Bool = false) {
        countdownTimer?.invalidate()
        countdownTimer = nil
        AlarmAudioService.shared.stop(alarmID: alarm.id)
        if runAction, alarm.action != .none {
            ShortcutsBridge.perform(alarm.action)
        }
        window?.orderOut(nil)
        window?.close()
        window = nil
        InterventionManager.shared.unregister(self)
        onDismiss?()
        onDismiss = nil
    }

    private func snooze(minutes: Int) {
        var copy = alarm
        copy.fireAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        copy.id = UUID()
        copy.repeatDaily = false
        copy.enabled = true
        ScheduleStore.shared.upsert(copy)
        dismiss(runAction: false)
    }

    private func act() {
        ShortcutsBridge.perform(alarm.action)
        dismiss(runAction: false)
    }

    private func startTakeoverCountdown() {
        takeoverSecondsRemaining = 2
        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceTakeoverCountdown() }
        }
    }

    private func advanceTakeoverCountdown() {
        takeoverSecondsRemaining -= 1
        guard takeoverSecondsRemaining <= 0 else { return }
        countdownTimer?.invalidate()
        countdownTimer = nil
        takeoverView?.enableDismiss()
    }
}

private final class SchedPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        becomesKeyOnlyIfNeeded = true
    }
}

// MARK: - Overlay (focus + takeover in one window — no orphan dim layer)

private enum OverlayStyle { case focus, takeover }

private final class OverlayView: NSView {
    let takeoverContent: TakeoverContent?

    init(
        alarm: SchedAlarm,
        style: OverlayStyle,
        dismiss: @escaping () -> Void,
        snooze: @escaping (Int) -> Void,
        act: @escaping () -> Void,
        onReadyToDismiss: (() -> Void)? = nil
    ) {
        takeoverContent = style == .takeover
            ? TakeoverContent(alarm: alarm, dismiss: dismiss, snooze: snooze, act: act)
            : nil
        super.init(frame: .zero)

        // The backdrop is deliberately inert. A stray click must never dismiss or
        // snooze a time-sensitive reminder while the user is working.
        let dim = NSView()
        dim.wantsLayer = true
        dim.layer?.backgroundColor = (style == .takeover ? SchedDesign.takeoverDim : SchedDesign.overlayDim).cgColor
        dim.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dim)
        NSLayoutConstraint.activate([
            dim.leadingAnchor.constraint(equalTo: leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: trailingAnchor),
            dim.topAnchor.constraint(equalTo: topAnchor),
            dim.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let panel: NSView
        switch style {
        case .focus:
            panel = FocusContent(alarm: alarm, dismiss: dismiss, snooze: snooze, act: act)
        case .takeover:
            panel = takeoverContent!
        }
        panel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(panel)
        NSLayoutConstraint.activate([
            panel.centerXAnchor.constraint(equalTo: centerXAnchor),
            panel.centerYAnchor.constraint(equalTo: centerYAnchor),
            panel.widthAnchor.constraint(equalToConstant: style == .takeover ? 480 : 420),
        ])
        _ = onReadyToDismiss
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

// MARK: - Buttons

@MainActor
private func schedButton(_ title: String, style: SchedButtonStyle = .ghost, action: @escaping () -> Void) -> NSButton {
    let button = SchedActionButton(title: title, actionHandler: action)
    button.bezelStyle = .rounded
    button.isBordered = true
    button.controlSize = .large
    button.font = SchedDesign.caption(12)
    button.focusRingType = .none
    button.translatesAutoresizingMaskIntoConstraints = false
    button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    switch style {
    case .ghost:
        button.contentTintColor = SchedDesign.inkMuted
    case .primary:
        button.contentTintColor = .white
        button.bezelColor = SchedDesign.accent
    case .primaryLight:
        button.contentTintColor = SchedDesign.ink
        button.bezelColor = SchedDesign.canvas
    }
    return button
}

private enum SchedButtonStyle { case ghost, primary, primaryLight }

// MARK: - Focus content

private final class FocusContent: NSView {
    init(alarm: SchedAlarm, dismiss: @escaping () -> Void, snooze: @escaping (Int) -> Void, act: @escaping () -> Void) {
        super.init(frame: .zero)
        let glass = SchedGlassSurface(
            cornerRadius: 20,
            tint: SchedDesign.bubbleSelected,
            interactive: false,
            stableWhenInactive: true
        )
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let host = glass.innerContentView

        let time = NSTextField(labelWithString: Self.timeString())
        time.font = SchedDesign.mono(12)
        time.textColor = SchedDesign.inkFaint
        SchedDesign.labelStyle(time)

        let title = NSTextField(wrappingLabelWithString: alarm.title)
        title.font = SchedDesign.title(24)
        SchedDesign.labelStyle(title)
        title.maximumNumberOfLines = 2

        let note = NSTextField(wrappingLabelWithString: alarm.note.isEmpty ? "Pause. Make the next action obvious." : alarm.note)
        note.font = SchedDesign.body(13)
        note.textColor = SchedDesign.inkMuted
        SchedDesign.labelStyle(note)
        note.maximumNumberOfLines = 2

        let rule = SchedDesign.hairline()
        let snoozeBtn = SchedSnoozeButton(defaultMinutes: ScheduleStore.shared.store.snoozeMinutes, action: snooze)
        let done = schedButton("Continue", style: .primary, action: dismiss)

        [time, title, note, rule, snoozeBtn, done].forEach { host.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            time.topAnchor.constraint(equalTo: host.topAnchor, constant: SchedDesign.pad),
            time.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: SchedDesign.pad),
            title.topAnchor.constraint(equalTo: time.bottomAnchor, constant: 6),
            title.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: SchedDesign.pad),
            title.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -SchedDesign.pad),
            note.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            note.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: SchedDesign.pad),
            note.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -SchedDesign.pad),
            rule.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: SchedDesign.pad),
            rule.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -SchedDesign.pad),
            rule.topAnchor.constraint(equalTo: note.isHidden ? title.bottomAnchor : note.bottomAnchor, constant: SchedDesign.padTight),
            snoozeBtn.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: SchedDesign.pad),
            snoozeBtn.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -SchedDesign.pad),
            done.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -SchedDesign.pad),
            done.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -SchedDesign.pad),
            heightAnchor.constraint(equalToConstant: 220),
        ])
        if alarm.action != .none {
            let run = schedButton("Run", style: .primaryLight, action: act)
            host.addSubview(run)
            run.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                run.trailingAnchor.constraint(equalTo: done.leadingAnchor, constant: -8),
                run.bottomAnchor.constraint(equalTo: done.bottomAnchor),
            ])
        }
    }

    private static func timeString() -> String {
        SchedTimeFormat.string(from: .now)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

// MARK: - Takeover content (card on dim, not opaque fullscreen)

private final class TakeoverContent: NSView {
    private var dismissButton: NSButton?

    init(alarm: SchedAlarm, dismiss: @escaping () -> Void, snooze: @escaping (Int) -> Void, act: @escaping () -> Void) {
        super.init(frame: .zero)
        let glass = SchedGlassSurface(
            cornerRadius: 22,
            tint: SchedDesign.bubbleSelected,
            interactive: false,
            stableWhenInactive: true
        )
        glass.translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        let host = glass.innerContentView

        let title = NSTextField(wrappingLabelWithString: alarm.title)
        title.font = SchedDesign.title(28)
        title.alignment = .center
        SchedDesign.labelStyle(title)
        title.maximumNumberOfLines = 2

        let note = NSTextField(wrappingLabelWithString: alarm.note.isEmpty ? "Pause. Choose what matters next." : alarm.note)
        note.font = SchedDesign.body(14)
        note.textColor = SchedDesign.inkMuted
        note.alignment = .center
        SchedDesign.labelStyle(note)
        note.maximumNumberOfLines = 2

        let done = schedButton("Continue", style: .primary, action: dismiss)
        done.isEnabled = false
        done.alphaValue = 0.35
        dismissButton = done

        let snoozeBtn = SchedSnoozeButton(defaultMinutes: ScheduleStore.shared.store.snoozeMinutes, action: snooze)

        var buttons: [NSView] = [snoozeBtn]
        if alarm.action != .none {
            let run = schedButton("Run", style: .primaryLight, action: act)
            buttons.append(run)
        }
        buttons.append(done)
        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

        let content = NSStackView(views: [title, note, SchedDesign.hairline(), buttonRow])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 8
        content.setCustomSpacing(18, after: note)
        content.setCustomSpacing(16, after: content.arrangedSubviews[2])
        content.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: host.topAnchor, constant: 24),
            content.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -24),
            content.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -24),
            title.widthAnchor.constraint(equalTo: content.widthAnchor),
            note.widthAnchor.constraint(equalTo: content.widthAnchor),
            content.arrangedSubviews[2].widthAnchor.constraint(equalTo: content.widthAnchor),
            widthAnchor.constraint(equalToConstant: 480),
            heightAnchor.constraint(equalToConstant: 230),
        ])
    }

    func enableDismiss() {
        dismissButton?.isEnabled = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            dismissButton?.animator().alphaValue = 1
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

// MARK: - Button helper

@MainActor
private final class SchedActionButton: NSButton {
    private let actionHandler: () -> Void

    init(title: String, actionHandler: @escaping () -> Void) {
        self.actionHandler = actionHandler
        super.init(frame: .zero)
        self.title = title
        target = self
        action = #selector(invokeAction)
    }

    @objc private func invokeAction() {
        actionHandler()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}
