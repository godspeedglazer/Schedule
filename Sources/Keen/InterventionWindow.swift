import AppKit
import Foundation

@MainActor
final class InterventionWindowController: NSWindowController, NSWindowDelegate {
    private static let gentleOriginKey = "Sched.GentleReminderOrigin"
    private let alarm: KeenAlarm
    private var onDismiss: (() -> Void)?
    private var countdownTimer: Timer?
    private var takeoverSecondsRemaining = 2
    private var audioTimer: Timer?

    init(alarm: KeenAlarm, onDismiss: @escaping () -> Void) {
        self.alarm = alarm
        self.onDismiss = onDismiss

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let window: NSWindow

        switch alarm.level {
        case .gentle:
            let size = NSSize(width: 440, height: 166)
            let origin = Self.restoredGentleOrigin(size: size, fallbackScreen: screen)
            window = KeenPanel(
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
            window = KeenPanel(
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
            window.contentView = KeenGentleToast(
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

        let preferences = ScheduleStore.shared.store
        if preferences.playSoundOnAlert && preferences.repeatSoundOnAlert {
            audioTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.playReminderSound() }
            }
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
        audioTimer?.invalidate()
        audioTimer = nil
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

    private func playReminderSound() {
        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }
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

private final class KeenPanel: NSPanel {
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
        alarm: KeenAlarm,
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
        dim.layer?.backgroundColor = (style == .takeover ? KeenDesign.takeoverDim : KeenDesign.overlayDim).cgColor
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
private func keenButton(_ title: String, style: KeenButtonStyle = .ghost, action: @escaping () -> Void) -> NSButton {
    let button = NSButton(title: title, target: nil, action: nil)
    button.bezelStyle = .rounded
    button.isBordered = true
    button.controlSize = .large
    button.font = KeenDesign.caption(12)
    button.focusRingType = .none
    button.translatesAutoresizingMaskIntoConstraints = false
    button.heightAnchor.constraint(equalToConstant: 34).isActive = true
    button.onAction = action
    switch style {
    case .ghost:
        button.contentTintColor = KeenDesign.inkMuted
    case .primary:
        button.contentTintColor = .white
        button.bezelColor = KeenDesign.accent
    case .primaryLight:
        button.contentTintColor = KeenDesign.ink
        button.bezelColor = KeenDesign.canvas
    }
    return button
}

private enum KeenButtonStyle { case ghost, primary, primaryLight }

// MARK: - Focus content

private final class FocusContent: NSView {
    init(alarm: KeenAlarm, dismiss: @escaping () -> Void, snooze: @escaping (Int) -> Void, act: @escaping () -> Void) {
        super.init(frame: .zero)
        let glass = KeenGlassSurface(
            cornerRadius: 20,
            tint: KeenDesign.bubbleSelected,
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
        time.font = KeenDesign.mono(12)
        time.textColor = KeenDesign.inkFaint
        KeenDesign.labelStyle(time)

        let title = NSTextField(wrappingLabelWithString: alarm.title)
        title.font = KeenDesign.title(24)
        KeenDesign.labelStyle(title)
        title.maximumNumberOfLines = 2

        let note = NSTextField(wrappingLabelWithString: alarm.note.isEmpty ? "Pause. Make the next action obvious." : alarm.note)
        note.font = KeenDesign.body(13)
        note.textColor = KeenDesign.inkMuted
        KeenDesign.labelStyle(note)
        note.maximumNumberOfLines = 2

        let rule = KeenDesign.hairline()
        let snoozeBtn = KeenSnoozeButton(defaultMinutes: ScheduleStore.shared.store.snoozeMinutes, action: snooze)
        let done = keenButton("Continue", style: .primary, action: dismiss)

        [time, title, note, rule, snoozeBtn, done].forEach { host.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            time.topAnchor.constraint(equalTo: host.topAnchor, constant: KeenDesign.pad),
            time.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: KeenDesign.pad),
            title.topAnchor.constraint(equalTo: time.bottomAnchor, constant: 6),
            title.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: KeenDesign.pad),
            title.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -KeenDesign.pad),
            note.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            note.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: KeenDesign.pad),
            note.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -KeenDesign.pad),
            rule.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: KeenDesign.pad),
            rule.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -KeenDesign.pad),
            rule.topAnchor.constraint(equalTo: note.isHidden ? title.bottomAnchor : note.bottomAnchor, constant: KeenDesign.padTight),
            snoozeBtn.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: KeenDesign.pad),
            snoozeBtn.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -KeenDesign.pad),
            done.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -KeenDesign.pad),
            done.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -KeenDesign.pad),
            heightAnchor.constraint(equalToConstant: 220),
        ])
        if alarm.action != .none {
            let run = keenButton("Run", style: .primaryLight, action: act)
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

    init(alarm: KeenAlarm, dismiss: @escaping () -> Void, snooze: @escaping (Int) -> Void, act: @escaping () -> Void) {
        super.init(frame: .zero)
        let glass = KeenGlassSurface(
            cornerRadius: 22,
            tint: KeenDesign.bubbleSelected,
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
        title.font = KeenDesign.title(28)
        title.alignment = .center
        KeenDesign.labelStyle(title)
        title.maximumNumberOfLines = 2

        let note = NSTextField(wrappingLabelWithString: alarm.note.isEmpty ? "Pause. Choose what matters next." : alarm.note)
        note.font = KeenDesign.body(14)
        note.textColor = KeenDesign.inkMuted
        note.alignment = .center
        KeenDesign.labelStyle(note)
        note.maximumNumberOfLines = 2

        let done = keenButton("Continue", style: .primary, action: dismiss)
        done.isEnabled = false
        done.alphaValue = 0.35
        dismissButton = done

        let snoozeBtn = KeenSnoozeButton(defaultMinutes: ScheduleStore.shared.store.snoozeMinutes, action: snooze)

        var buttons: [NSView] = [snoozeBtn]
        if alarm.action != .none {
            let run = keenButton("Run", style: .primaryLight, action: act)
            buttons.append(run)
        }
        buttons.append(done)
        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 10

        let content = NSStackView(views: [title, note, KeenDesign.hairline(), buttonRow])
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

private final class ButtonTarget: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func fire() { action() }
}

@MainActor
private var buttonTargets: [ObjectIdentifier: ButtonTarget] = [:]

private extension NSButton {
    var onAction: (() -> Void)? {
        get { nil }
        set {
            guard let newValue else { return }
            let target = ButtonTarget(newValue)
            buttonTargets[ObjectIdentifier(self)] = target
            self.target = target
            self.action = #selector(ButtonTarget.fire)
        }
    }
}
