import AppKit
import Foundation

struct SchedAlertGestureMetrics {
    /// A brief dwell separates an intentional notification gesture from a
    /// normal click or an attempt to move the persistent corner card.
    static let intentDelay: TimeInterval = 0.12
    static let swipeThreshold: CGFloat = 32
    static let holdDuration: TimeInterval = 0.42

    static func outwardDistance(deltaX: CGFloat, rightEdge: Bool) -> CGFloat {
        max(0, deltaX * (rightEdge ? 1 : -1))
    }

    static func swipeProgress(deltaX: CGFloat, rightEdge: Bool) -> CGFloat {
        min(1, outwardDistance(deltaX: deltaX, rightEdge: rightEdge) / swipeThreshold)
    }
}

@MainActor
final class InterventionWindowController: NSWindowController, NSWindowDelegate {
    private static let cornerOriginKey = "Sched.CornerReminderOrigin"
    private let alarm: SchedAlarm
    private var onDismiss: (() -> Void)?
    private var bannerDismissWorkItem: DispatchWorkItem?
    private var isClosing = false
    var alarmID: UUID { alarm.id }

    init(alarm: SchedAlarm, onDismiss: @escaping () -> Void) {
        self.alarm = alarm
        self.onDismiss = onDismiss

        let screen = NSScreen.main ?? NSScreen.screens.first!
        let frame: NSRect
        switch alarm.level {
        case .gentle:
            let size = NSSize(width: 368, height: alarm.note.isEmpty ? 72 : 104)
            frame = NSRect(origin: Self.restoredCornerOrigin(size: size, screen: screen), size: size)
        case .focus:
            let size = NSSize(width: 360, height: 88)
            frame = NSRect(origin: Self.edgeOrigin(size: size, screen: screen), size: size)
        case .takeover:
            frame = screen.frame
        }

        let panel = SchedInterventionPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = alarm.level == .takeover ? .screenSaver : .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = alarm.level != .takeover
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        if alarm.level == .takeover {
            // The takeover is intentionally an actual system-coloured screen,
            // not a darkened desktop with a custom card floating above it.
            panel.appearance = nil
        } else {
            SchedDesign.applyWindowAppearance(panel)
        }

        super.init(window: panel)
        panel.delegate = self

        let complete: () -> Void = { [weak self] in self?.complete() }
        let snooze: (Int) -> Void = { [weak self] minutes in self?.snooze(minutes: minutes) }
        let run: (() -> Void)? = alarm.action == .none ? nil : { [weak self] in self?.runAction() }

        switch alarm.level {
        case .gentle:
            panel.contentView = SchedEdgeReminderView(
                alarm: alarm,
                format: .corner,
                defaultSnooze: ScheduleStore.shared.store.snoozeMinutes,
                complete: complete,
                snooze: snooze,
                runAction: run
            )
        case .focus:
            panel.contentView = SchedEdgeReminderView(
                alarm: alarm,
                format: .banner,
                defaultSnooze: ScheduleStore.shared.store.snoozeMinutes,
                complete: complete,
                snooze: snooze,
                runAction: run
            )
        case .takeover:
            panel.contentView = SchedConversationReminderView(
                alarm: alarm,
                defaultSnooze: ScheduleStore.shared.store.snoozeMinutes,
                complete: complete,
                snooze: snooze,
                runAction: run
            )
        }

        panel.initialFirstResponder = panel.contentView
        present(panel)
        InterventionManager.shared.register(self)
        if alarm.level == .focus {
            // A banner is a transient, low-friction signal. Persistent work is
            // represented by the corner message; the banner must leave on its own.
            let dismiss = DispatchWorkItem { [weak self] in self?.forceDismiss() }
            bannerDismissWorkItem = dismiss
            DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: dismiss)
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func windowDidMove(_ notification: Notification) {
        guard alarm.level == .gentle, let window else { return }
        UserDefaults.standard.set(NSStringFromPoint(window.frame.origin), forKey: Self.cornerOriginKey)
    }

    func forceDismiss() {
        closeReminder()
    }

    private func present(_ panel: NSPanel) {
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        if alarm.level == .takeover {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            panel.orderFrontRegardless()
        }
        panel.makeFirstResponder(panel.contentView)
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private static func edgeOrigin(size: NSSize, screen: NSScreen) -> NSPoint {
        NSPoint(
            x: screen.visibleFrame.maxX - size.width - 18,
            y: screen.visibleFrame.maxY - size.height - 12
        )
    }

    private static func restoredCornerOrigin(size: NSSize, screen: NSScreen) -> NSPoint {
        let fallback = edgeOrigin(size: size, screen: screen)
        guard let raw = UserDefaults.standard.string(forKey: cornerOriginKey) else { return fallback }
        let saved = NSPointFromString(raw)
        let savedFrame = NSRect(origin: saved, size: size)
        let targetScreen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(savedFrame) }) ?? screen
        let visible = targetScreen.visibleFrame
        return NSPoint(
            x: min(max(saved.x, visible.minX), visible.maxX - size.width),
            y: min(max(saved.y, visible.minY), visible.maxY - size.height)
        )
    }

    private func complete() {
        if alarm.action != .none { ShortcutsBridge.perform(alarm.action) }
        closeReminder()
    }

    private func snooze(minutes: Int) {
        var copy = alarm
        copy.fireAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        copy.id = UUID()
        copy.repeatDaily = false
        copy.enabled = true
        ScheduleStore.shared.upsert(copy)
        closeReminder()
    }

    private func runAction() {
        ShortcutsBridge.perform(alarm.action)
        closeReminder()
    }

    private func closeReminder() {
        guard !isClosing else { return }
        isClosing = true
        bannerDismissWorkItem?.cancel()
        bannerDismissWorkItem = nil
        AlarmAudioService.shared.stop(alarmID: alarm.id)
        guard let window, alarm.level == .takeover,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finalizeClose()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                self?.finalizeClose()
            }
        }
    }

    private func finalizeClose() {
        window?.orderOut(nil)
        window?.close()
        window = nil
        InterventionManager.shared.unregister(self)
        onDismiss?()
        onDismiss = nil
    }
}

private final class SchedInterventionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        becomesKeyOnlyIfNeeded = false
    }
}

private enum SchedEdgeReminderFormat { case corner, banner }

@MainActor
private final class SchedEdgeReminderView: NSView {
    private let format: SchedEdgeReminderFormat
    private let defaultSnooze: Int
    private let completeHandler: () -> Void
    private let snoozeHandler: (Int) -> Void
    private let runActionHandler: (() -> Void)?
    private let progress = NSView()
    private var progressWidth: NSLayoutConstraint!
    private var gestureTimer: Timer?
    private var holdStartedAt: TimeInterval = 0
    private var initialMouse = NSPoint.zero
    private var initialWindowOrigin = NSPoint.zero
    private var rightEdge = true
    private var isDragging = false
    private var isOutwardDrag = false
    private var intentLocked = false
    private var didPerformIntentHaptic = false
    private var didComplete = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    init(
        alarm: SchedAlarm,
        format: SchedEdgeReminderFormat,
        defaultSnooze: Int,
        complete: @escaping () -> Void,
        snooze: @escaping (Int) -> Void,
        runAction: (() -> Void)?
    ) {
        self.format = format
        self.defaultSnooze = defaultSnooze
        completeHandler = complete
        snoozeHandler = snooze
        runActionHandler = runAction
        super.init(frame: .zero)

        wantsLayer = true
        progress.wantsLayer = true
        progress.layer?.cornerRadius = 1
        progress.layer?.backgroundColor = SchedDesign.accent.cgColor
        progress.alphaValue = 0
        progressWidth = progress.widthAnchor.constraint(equalToConstant: 0)

        switch format {
        case .corner:
            // The gentle reminder is deliberately a single incoming message at
            // the screen edge—not a miniature dashboard or imitation toast.
            layer?.backgroundColor = NSColor.clear.cgColor
            let message = SchedMessageBubble(
                title: alarm.title,
                side: .incoming,
                fill: NSColor.windowBackgroundColor,
                titleColor: .labelColor
            )
            message.wantsLayer = true
            message.layer?.shadowColor = NSColor.black.cgColor
            message.layer?.shadowOpacity = 0.18
            message.layer?.shadowRadius = 14
            message.layer?.shadowOffset = CGSize(width: 0, height: -3)
            addSubview(message)
            addSubview(progress)
            message.translatesAutoresizingMaskIntoConstraints = false
            progress.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                message.leadingAnchor.constraint(equalTo: leadingAnchor),
                message.trailingAnchor.constraint(equalTo: trailingAnchor),
                message.topAnchor.constraint(equalTo: topAnchor),
                message.bottomAnchor.constraint(equalTo: bottomAnchor),
                progress.leadingAnchor.constraint(equalTo: message.leadingAnchor, constant: 18),
                progress.bottomAnchor.constraint(equalTo: message.bottomAnchor, constant: 7),
                progress.heightAnchor.constraint(equalToConstant: 2),
                progressWidth,
            ])
        case .banner:
            // Focus is an actual transient banner: a compact side strip with a
            // single line of intent, visibly different from the message card.
            layer?.cornerRadius = 14
            layer?.cornerCurve = .continuous
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = 0.16
            layer?.shadowRadius = 14
            layer?.shadowOffset = CGSize(width: 0, height: -3)

            let stripe = NSView()
            stripe.wantsLayer = true
            stripe.layer?.backgroundColor = SchedDesign.levelColor(alarm.level).cgColor
            stripe.layer?.cornerRadius = 2
            let appName = NSTextField(labelWithString: "SCHED")
            appName.font = SchedDesign.section(10)
            SchedDesign.label(appName, color: SchedDesign.inkMuted)
            let title = NSTextField(labelWithString: alarm.title)
            title.font = SchedDesign.title(15)
            title.lineBreakMode = .byTruncatingTail
            title.maximumNumberOfLines = 1
            SchedDesign.label(title)
            [stripe, appName, title, progress].forEach { addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
            NSLayoutConstraint.activate([
                stripe.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
                stripe.topAnchor.constraint(equalTo: topAnchor, constant: 15),
                stripe.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -15),
                stripe.widthAnchor.constraint(equalToConstant: 3),
                appName.leadingAnchor.constraint(equalTo: stripe.trailingAnchor, constant: 12),
                appName.topAnchor.constraint(equalTo: topAnchor, constant: 17),
                title.leadingAnchor.constraint(equalTo: appName.leadingAnchor),
                title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
                title.topAnchor.constraint(equalTo: appName.bottomAnchor, constant: 3),
                progress.leadingAnchor.constraint(equalTo: leadingAnchor),
                progress.bottomAnchor.constraint(equalTo: bottomAnchor),
                progress.heightAnchor.constraint(equalToConstant: 2),
                progressWidth,
            ])
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(alarm.title)
        setAccessibilityHelp("Reminder controls")
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        guard !didComplete, let window else { return }
        window.makeFirstResponder(self)
        initialMouse = NSEvent.mouseLocation
        initialWindowOrigin = window.frame.origin
        let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        rightEdge = window.frame.midX >= visible.midX
        isDragging = false
        isOutwardDrag = false
        intentLocked = false
        didPerformIntentHaptic = false
        holdStartedAt = ProcessInfo.processInfo.systemUptime
        updateProgress(0)
        startGestureTimer()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didComplete, let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - initialMouse.x
        let dy = current.y - initialMouse.y
        guard hypot(dx, dy) > 3 else { return }
        isDragging = true

        // Before the short intent dwell, a corner card remains a normal movable
        // Mac panel. The banner simply snaps back. Once intent is established,
        // only the compact outward sleep gesture is interpreted.
        if !intentLocked {
            cancelGesture()
            if format == .corner {
                window.setFrameOrigin(NSPoint(x: initialWindowOrigin.x + dx, y: initialWindowOrigin.y + dy))
            }
            return
        }

        let outward = SchedAlertGestureMetrics.outwardDistance(deltaX: dx, rightEdge: rightEdge)
        isOutwardDrag = outward > 0 && abs(dx) >= abs(dy)
        if isOutwardDrag {
            let swipeProgress = SchedAlertGestureMetrics.swipeProgress(deltaX: dx, rightEdge: rightEdge)
            window.setFrameOrigin(NSPoint(x: initialWindowOrigin.x + dx, y: initialWindowOrigin.y))
            window.alphaValue = 1 - swipeProgress * 0.22
            updateProgress(swipeProgress)
        } else {
            window.setFrameOrigin(initialWindowOrigin)
            updateProgress(0)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard !didComplete else { return }
        cancelGesture()
        guard let window else { return }
        let dx = NSEvent.mouseLocation.x - initialMouse.x
        let swipeProgress = SchedAlertGestureMetrics.swipeProgress(deltaX: dx, rightEdge: rightEdge)
        if isOutwardDrag, swipeProgress >= 1 {
            didComplete = true
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            snoozeHandler(defaultSnooze)
            return
        }
        if isOutwardDrag {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                window.setFrameOrigin(initialWindowOrigin)
                window.alphaValue = 1
            } else {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().setFrameOrigin(initialWindowOrigin)
                    window.animator().alphaValue = 1
                }
            }
        }
        updateProgress(0)
        isDragging = false
        isOutwardDrag = false
    }

    override func keyDown(with event: NSEvent) {
        let towardEdge = (rightEdge && event.keyCode == 124) || (!rightEdge && event.keyCode == 123)
        if towardEdge {
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            snoozeHandler(defaultSnooze)
        } else if event.keyCode == 36 && event.modifierFlags.contains(.command) {
            completeHandler()
        } else if event.keyCode == 49 {
            beginKeyboardHold()
        } else {
            super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49, !didComplete {
            cancelGesture()
            updateProgress(0)
        } else {
            super.keyUp(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        completeHandler()
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Snooze \(defaultSnooze) Minutes", action: #selector(snoozeFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Complete", action: #selector(completeFromMenu), keyEquivalent: "")
        if runActionHandler != nil {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Run Action", action: #selector(runFromMenu), keyEquivalent: "")
        }
        menu.items.forEach { $0.target = self }
        return menu
    }

    private func beginKeyboardHold() {
        guard gestureTimer == nil else { return }
        holdStartedAt = ProcessInfo.processInfo.systemUptime
        intentLocked = true
        startGestureTimer()
    }

    private func startGestureTimer() {
        gestureTimer?.invalidate()
        let timer = Timer(timeInterval: 0.02, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceGesture() }
        }
        timer.tolerance = 0.005
        gestureTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func advanceGesture() {
        guard !didComplete else { return }
        let elapsed = ProcessInfo.processInfo.systemUptime - holdStartedAt
        if !intentLocked, elapsed >= SchedAlertGestureMetrics.intentDelay {
            intentLocked = true
            if !didPerformIntentHaptic {
                didPerformIntentHaptic = true
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        guard !isDragging else { return }
        let completionWindow = max(0.01, SchedAlertGestureMetrics.holdDuration - SchedAlertGestureMetrics.intentDelay)
        let progress = min(1, max(0, (elapsed - SchedAlertGestureMetrics.intentDelay) / completionWindow))
        updateProgress(intentLocked ? progress : 0)
        if progress >= 1 {
            didComplete = true
            cancelGesture()
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            completeHandler()
        }
    }

    private func cancelGesture() {
        gestureTimer?.invalidate()
        gestureTimer = nil
    }

    private func updateProgress(_ value: CGFloat) {
        progress.alphaValue = value > 0 ? 1 : 0
        progressWidth.constant = max(0, bounds.width * value)
        needsLayout = true
    }

    @objc private func snoozeFromMenu() { snoozeHandler(defaultSnooze) }
    @objc private func completeFromMenu() { completeHandler() }
    @objc private func runFromMenu() { runActionHandler?() }
}

@MainActor
final class SchedMessageBubble: NSView {
    enum Side { case incoming, outgoing }

    private let side: Side
    private let fillColor: NSColor

    init(
        title: String,
        detail: String? = nil,
        side: Side,
        fill: NSColor,
        titleColor: NSColor = SchedDesign.ink,
        detailColor: NSColor = SchedDesign.inkMuted
    ) {
        self.side = side
        fillColor = fill
        super.init(frame: .zero)

        let titleLabel = NSTextField(wrappingLabelWithString: title)
        titleLabel.font = SchedDesign.body(15)
        titleLabel.maximumNumberOfLines = 3
        SchedDesign.label(titleLabel, color: titleColor)

        var views: [NSView] = [titleLabel]
        if let detail, !detail.isEmpty {
            let detailLabel = NSTextField(wrappingLabelWithString: detail)
            detailLabel.font = SchedDesign.body(12)
            detailLabel.maximumNumberOfLines = 3
            SchedDesign.label(detailLabel, color: detailColor)
            views.append(detailLabel)
        }
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let leading: CGFloat = side == .incoming ? 22 : 16
        let trailing: CGFloat = side == .outgoing ? 22 : 16
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leading),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -trailing),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            widthAnchor.constraint(lessThanOrEqualToConstant: 390),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(detail.map { "\(title). \($0)" } ?? title)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        fillColor.setFill()
        let tail: CGFloat = 10
        let body = side == .incoming
            ? bounds.insetBy(dx: 0, dy: 0).offsetBy(dx: tail, dy: 0).withWidth(bounds.width - tail)
            : bounds.withWidth(bounds.width - tail)
        NSBezierPath(roundedRect: body.insetBy(dx: 0.5, dy: 0.5), xRadius: 18, yRadius: 18).fill()
        let path = NSBezierPath()
        if side == .outgoing {
            path.move(to: NSPoint(x: body.maxX - 16, y: body.minY + 3))
            path.curve(to: NSPoint(x: bounds.maxX, y: bounds.minY), controlPoint1: NSPoint(x: body.maxX - 4, y: body.minY + 2), controlPoint2: NSPoint(x: body.maxX + 1, y: body.minY))
            path.line(to: NSPoint(x: body.maxX - 2, y: body.minY + 19))
        } else {
            path.move(to: NSPoint(x: body.minX + 16, y: body.minY + 3))
            path.curve(to: NSPoint(x: bounds.minX, y: bounds.minY), controlPoint1: NSPoint(x: body.minX + 4, y: body.minY + 2), controlPoint2: NSPoint(x: body.minX - 1, y: body.minY))
            path.line(to: NSPoint(x: body.minX + 2, y: body.minY + 19))
        }
        path.close()
        path.fill()
    }
}

private extension NSRect {
    func withWidth(_ width: CGFloat) -> NSRect {
        NSRect(x: origin.x, y: origin.y, width: width, height: height)
    }
}

@MainActor
private final class SchedConversationReminderView: NSView, NSTextFieldDelegate {
    private let defaultSnooze: Int
    private let completeHandler: () -> Void
    private let snoozeHandler: (Int) -> Void
    private let runActionHandler: (() -> Void)?
    private let messages = NSStackView()
    private let replyField = NSTextField()
    private var didReply = false

    override var acceptsFirstResponder: Bool { true }

    init(
        alarm: SchedAlarm,
        defaultSnooze: Int,
        complete: @escaping () -> Void,
        snooze: @escaping (Int) -> Void,
        runAction: (() -> Void)?
    ) {
        self.defaultSnooze = defaultSnooze
        completeHandler = complete
        snoozeHandler = snooze
        runActionHandler = runAction
        super.init(frame: .zero)

        wantsLayer = true
        // This deliberately occupies the whole display. The conversation is
        // content on the screen, not a pane placed on an artificial dimmer.
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let header = NSTextField(labelWithString: "Earlier")
        header.font = SchedDesign.title(15)
        SchedDesign.label(header, color: .labelColor)

        let more = NSButton(
            image: NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "Reminder actions") ?? NSImage(),
            target: self,
            action: #selector(showActions(_:))
        )
        more.isBordered = false
        more.contentTintColor = .secondaryLabelColor
        more.toolTip = "Reminder actions"

        messages.orientation = .vertical
        messages.alignment = .leading
        messages.spacing = 10
        messages.translatesAutoresizingMaskIntoConstraints = false

        let request = SchedMessageBubble(
            title: "Remind me at \(SchedTimeFormat.string(from: alarm.fireAt)) to \(alarm.title).",
            side: .outgoing,
            fill: .systemBlue,
            titleColor: .white,
            detailColor: .white
        )
        addMessage(request, side: .outgoing, animated: false)

        let divider = schedConversationDivider("Now")
        divider.translatesAutoresizingMaskIntoConstraints = false
        messages.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: messages.widthAnchor).isActive = true

        let reminder = SchedMessageBubble(
            title: alarm.title,
            side: .incoming,
            fill: .controlBackgroundColor,
            titleColor: .labelColor,
            detailColor: .secondaryLabelColor
        )
        addMessage(reminder, side: .incoming, animated: true, delay: 0.20)
        if !alarm.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let context = SchedMessageBubble(
                title: alarm.note,
                side: .incoming,
                fill: .controlBackgroundColor,
                titleColor: .labelColor,
                detailColor: .secondaryLabelColor
            )
            addMessage(context, side: .incoming, animated: true, delay: 0.54)
        }

        let composer = NSView()
        composer.wantsLayer = true
        composer.layer?.cornerRadius = 22
        composer.layer?.cornerCurve = .continuous
        composer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        composer.layer?.borderWidth = 1
        composer.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.55).cgColor
        composer.layer?.shadowColor = NSColor.black.cgColor
        composer.layer?.shadowOpacity = 0.08
        composer.layer?.shadowRadius = 8
        composer.layer?.shadowOffset = CGSize(width: 0, height: -2)

        replyField.placeholderString = "Send a reply to complete"
        replyField.font = SchedDesign.body(15)
        replyField.textColor = .labelColor
        replyField.backgroundColor = .clear
        replyField.isBezeled = false
        replyField.focusRingType = .none
        replyField.delegate = self
        replyField.target = self
        replyField.action = #selector(sendReply)

        let send = NSButton(
            image: NSImage(systemSymbolName: "arrow.up.circle.fill", accessibilityDescription: "Send reply") ?? NSImage(),
            target: self,
            action: #selector(sendReply)
        )
        send.isBordered = false
        send.contentTintColor = .systemBlue
        send.toolTip = "Send reply"

        [header, more, messages, composer, replyField, send].forEach {
            addSubview($0)
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        NSLayoutConstraint.activate([
            header.centerXAnchor.constraint(equalTo: centerXAnchor),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 34),
            more.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30),
            more.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            more.widthAnchor.constraint(equalToConstant: 28),
            more.heightAnchor.constraint(equalToConstant: 28),

            messages.centerXAnchor.constraint(equalTo: centerXAnchor),
            messages.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 34),
            messages.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 44),
            messages.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -44),
            messages.widthAnchor.constraint(lessThanOrEqualToConstant: 500),

            composer.centerXAnchor.constraint(equalTo: centerXAnchor),
            composer.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 44),
            composer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -44),
            composer.widthAnchor.constraint(equalTo: messages.widthAnchor),
            composer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -38),
            composer.heightAnchor.constraint(equalToConstant: 48),
            messages.bottomAnchor.constraint(lessThanOrEqualTo: composer.topAnchor, constant: -30),

            replyField.leadingAnchor.constraint(equalTo: composer.leadingAnchor, constant: 16),
            replyField.trailingAnchor.constraint(equalTo: send.leadingAnchor, constant: -8),
            replyField.centerYAnchor.constraint(equalTo: composer.centerYAnchor),
            replyField.heightAnchor.constraint(equalToConstant: 30),
            send.trailingAnchor.constraint(equalTo: composer.trailingAnchor, constant: -10),
            send.centerYAnchor.constraint(equalTo: composer.centerYAnchor),
            send.widthAnchor.constraint(equalToConstant: 30),
            send.heightAnchor.constraint(equalToConstant: 30),
        ])

        setAccessibilityElement(false)
        DispatchQueue.main.async { [weak self] in self?.window?.makeFirstResponder(self?.replyField) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape is the unobtrusive quick defer.
            snoozeHandler(defaultSnooze)
        } else {
            super.keyDown(with: event)
        }
    }

    private func addMessage(_ bubble: SchedMessageBubble, side: SchedMessageBubble.Side, animated: Bool, delay: TimeInterval = 0) {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(bubble)
        bubble.translatesAutoresizingMaskIntoConstraints = false
        if side == .incoming {
            NSLayoutConstraint.activate([
                bubble.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                bubble.topAnchor.constraint(equalTo: row.topAnchor),
                bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                bubble.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
            ])
        } else {
            NSLayoutConstraint.activate([
                bubble.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                bubble.topAnchor.constraint(equalTo: row.topAnchor),
                bubble.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                bubble.leadingAnchor.constraint(greaterThanOrEqualTo: row.leadingAnchor),
            ])
        }
        messages.addArrangedSubview(row)
        row.widthAnchor.constraint(equalTo: messages.widthAnchor).isActive = true
        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        row.alphaValue = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                row.animator().alphaValue = 1
            }
            NSSound(named: NSSound.Name("Pop"))?.play()
        }
    }

    @objc private func sendReply() {
        let text = SchedTextLimits.clean(replyField.stringValue, limit: SchedTextLimits.note)
        guard !text.isEmpty, !didReply else {
            NSSound.beep()
            return
        }
        didReply = true
        replyField.stringValue = ""
        replyField.isEnabled = false
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        let sent = SchedMessageBubble(title: text, side: .outgoing, fill: .systemBlue, titleColor: .white, detailColor: .white)
        addMessage(sent, side: .outgoing, animated: true)
        NSSound(named: NSSound.Name("Sent Message"))?.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in self?.completeHandler() }
    }

    @objc private func showActions(_ sender: NSButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Snooze \(defaultSnooze) Minutes", action: #selector(snoozeFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Snooze Until Tomorrow", action: #selector(snoozeTomorrow), keyEquivalent: "")
        if runActionHandler != nil {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Run Action", action: #selector(runFromMenu), keyEquivalent: "")
        }
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc private func snoozeFromMenu() { snoozeHandler(defaultSnooze) }
    @objc private func snoozeTomorrow() { snoozeHandler(24 * 60) }
    @objc private func runFromMenu() { runActionHandler?() }
}

@MainActor
private func schedConversationDivider(_ text: String) -> NSView {
    let label = NSTextField(labelWithString: text)
    label.font = SchedDesign.caption(10)
    SchedDesign.label(label, color: SchedDesign.inkFaint)
    let left = SchedDesign.hairline()
    let right = SchedDesign.hairline()
    let row = NSStackView(views: [left, label, right])
    row.orientation = .horizontal
    row.alignment = .centerY
    row.spacing = 12
    left.widthAnchor.constraint(equalTo: right.widthAnchor).isActive = true
    return row
}

@MainActor
private func schedConversationButton(_ title: String, symbol: String, action: @escaping () -> Void) -> NSButton {
    let button = SchedClosureButton(title: title, actionHandler: action)
    button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    button.imagePosition = .imageLeading
    button.bezelStyle = .rounded
    button.controlSize = .large
    button.font = SchedDesign.caption(11)
    button.heightAnchor.constraint(equalToConstant: 42).isActive = true
    return button
}

@MainActor
private final class SchedClosureButton: NSButton {
    private let actionHandler: () -> Void

    init(title: String, actionHandler: @escaping () -> Void) {
        self.actionHandler = actionHandler
        super.init(frame: .zero)
        self.title = title
        target = self
        action = #selector(invoke)
    }

    @objc private func invoke() { actionHandler() }
    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}
