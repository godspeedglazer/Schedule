import AppKit

@MainActor
final class SchedCanvasView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradient.colors = [SchedDesign.canvas.cgColor, SchedDesign.canvasDeep.cgColor]
        gradient.startPoint = CGPoint(x: 0.15, y: 0)
        gradient.endPoint = CGPoint(x: 0.85, y: 1)
        layer?.insertSublayer(gradient, at: 0)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        gradient.frame = bounds
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let symbols = ["clock", "checkmark.circle", "bell", "timer", "sparkles", "calendar"]
        let points: [CGPoint] = [
            CGPoint(x: 0.16, y: 0.22), CGPoint(x: 0.84, y: 0.18),
            CGPoint(x: 0.70, y: 0.48), CGPoint(x: 0.22, y: 0.62),
            CGPoint(x: 0.82, y: 0.78), CGPoint(x: 0.46, y: 0.88),
        ]
        NSColor(calibratedWhite: 0.22, alpha: 0.10).set()
        for (index, point) in points.enumerated() {
            guard let image = NSImage(systemSymbolName: symbols[index], accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)) else { continue }
            let rect = NSRect(
                x: bounds.width * point.x - 12,
                y: bounds.height * point.y - 12,
                width: 24,
                height: 24
            )
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.42, respectFlipped: true, hints: nil)
        }
    }
}

@MainActor
final class SchedFlippedView: NSView {
    override var isFlipped: Bool { true }
}

struct SchedBottomFadeMetrics {
    static let depth: CGFloat = 52

    static func locations(viewportHeight: CGFloat, depth: CGFloat = depth) -> [NSNumber] {
        guard viewportHeight > 0 else { return [0, 0, 1] }
        let normalizedDepth = min(1, max(0, depth / viewportHeight))
        return [0, NSNumber(value: Double(1 - normalizedDepth)), 1]
    }
}

/// Keeps the visual depth of the list edge constant as the window changes size.
/// The mask belongs to the clip view so the vertical scroller remains crisp.
@MainActor
final class SchedBottomFadeScrollView: NSScrollView {
    private let fadeMask = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        fadeMask.colors = [
            NSColor.black.cgColor,
            NSColor.black.cgColor,
            NSColor.clear.cgColor,
        ]
        fadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        fadeMask.endPoint = CGPoint(x: 0.5, y: 1)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        refreshBottomFade()
    }

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        refreshBottomFade()
    }

    func refreshBottomFade() {
        guard let documentView else {
            contentView.layer?.mask = nil
            return
        }
        contentView.wantsLayer = true
        let visible = documentVisibleRect
        let documentBottom = documentView.bounds.maxY
        let hasHiddenContentBelow = visible.maxY < documentBottom - 1
        guard hasHiddenContentBelow, contentView.bounds.height > 1 else {
            contentView.layer?.mask = nil
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fadeMask.frame = contentView.bounds
        fadeMask.locations = SchedBottomFadeMetrics.locations(viewportHeight: contentView.bounds.height)
        contentView.layer?.mask = fadeMask
        CATransaction.commit()
    }
}

@MainActor
final class SchedGlassSurface: NSView {
    private let content = NSView()
    private var glassView: NSView?
    private var cornerRadius: CGFloat
    private var interactive: Bool
    private let stableWhenInactive: Bool
    private var currentTint: NSColor?

    var innerContentView: NSView { content }

    init(
        cornerRadius: CGFloat? = nil,
        tint: NSColor? = nil,
        interactive: Bool = false,
        stableWhenInactive: Bool = true
    ) {
        self.cornerRadius = cornerRadius ?? SchedDesign.cardRadius
        self.interactive = interactive
        self.stableWhenInactive = stableWhenInactive
        currentTint = tint
        super.init(frame: .zero)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        installGlass(tint: tint)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.06
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -3)
    }

    func updateTint(_ tint: NSColor?, selected: Bool = false) {
        currentTint = tint
        if stableWhenInactive {
            layer?.backgroundColor = stableSurfaceColor(tint).cgColor
        }
        if #available(macOS 26.0, *), let glass = glassView as? NSGlassEffectView {
            glass.tintColor = tint
        }
        layer?.shadowOpacity = selected ? 0.12 : 0.06
    }

    private func installGlass(tint: NSColor?) {
        glassView?.removeFromSuperview()
        if stableWhenInactive {
            layer?.cornerRadius = cornerRadius
            layer?.backgroundColor = stableSurfaceColor(tint).cgColor
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.white.withAlphaComponent(0.82).cgColor
            addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.topAnchor.constraint(equalTo: topAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            return
        }
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.translatesAutoresizingMaskIntoConstraints = false
            glass.cornerRadius = cornerRadius
            if let tint { glass.tintColor = tint }
            if #available(macOS 27.0, *) {
                glass.effectIsInteractive = interactive
            }
            glass.contentView = content
            addSubview(glass)
            NSLayoutConstraint.activate([
                glass.leadingAnchor.constraint(equalTo: leadingAnchor),
                glass.trailingAnchor.constraint(equalTo: trailingAnchor),
                glass.topAnchor.constraint(equalTo: topAnchor),
                glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            glassView = glass
        } else {
            let fx = NSVisualEffectView()
            fx.material = .hudWindow
            fx.blendingMode = .behindWindow
            fx.state = .active
            fx.wantsLayer = true
            fx.layer?.cornerRadius = cornerRadius
            fx.layer?.masksToBounds = true
            fx.translatesAutoresizingMaskIntoConstraints = false
            addSubview(fx)
            addSubview(content)
            NSLayoutConstraint.activate([
                fx.leadingAnchor.constraint(equalTo: leadingAnchor),
                fx.trailingAnchor.constraint(equalTo: trailingAnchor),
                fx.topAnchor.constraint(equalTo: topAnchor),
                fx.bottomAnchor.constraint(equalTo: bottomAnchor),
                content.leadingAnchor.constraint(equalTo: leadingAnchor),
                content.trailingAnchor.constraint(equalTo: trailingAnchor),
                content.topAnchor.constraint(equalTo: topAnchor),
                content.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
            glassView = fx
        }
    }

    private func stableSurfaceColor(_ tint: NSColor?) -> NSColor {
        let base = NSColor(calibratedRed: 0.985, green: 0.974, blue: 0.946, alpha: 1)
        guard let tint else { return base.withAlphaComponent(0.94) }
        let solidTint = tint.withAlphaComponent(1)
        return (base.blended(withFraction: 0.20, of: solidTint) ?? base).withAlphaComponent(0.94)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

@MainActor
final class SchedGlassContainer: NSView {
    let contentHost = NSView()

    init(spacing: CGFloat = 24) {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        contentHost.translatesAutoresizingMaskIntoConstraints = false

        if #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView()
            container.translatesAutoresizingMaskIntoConstraints = false
            container.spacing = spacing
            container.contentView = contentHost
            addSubview(container)
            NSLayoutConstraint.activate([
                container.leadingAnchor.constraint(equalTo: leadingAnchor),
                container.trailingAnchor.constraint(equalTo: trailingAnchor),
                container.topAnchor.constraint(equalTo: topAnchor),
                container.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        } else {
            addSubview(contentHost)
            NSLayoutConstraint.activate([
                contentHost.leadingAnchor.constraint(equalTo: leadingAnchor),
                contentHost.trailingAnchor.constraint(equalTo: trailingAnchor),
                contentHost.topAnchor.constraint(equalTo: topAnchor),
                contentHost.bottomAnchor.constraint(equalTo: bottomAnchor),
            ])
        }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

// MARK: - Buttons

@MainActor
final class SchedPrimaryButton: NSButton {
    init(_ title: String, action: Selector, target: AnyObject?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        bezelStyle = .rounded
        isBordered = true
        bezelColor = SchedDesign.accent
        contentTintColor = .white
        controlSize = .large
        font = SchedDesign.caption(12)
        appearance = SchedDesign.windowAppearance
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

@MainActor
final class SchedGhostButton: NSButton {
    init(_ title: String, action: Selector, target: AnyObject?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        bezelStyle = .rounded
        isBordered = true
        controlSize = .regular
        contentTintColor = SchedDesign.inkMuted
        font = SchedDesign.caption(12)
        appearance = SchedDesign.windowAppearance
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

@MainActor
final class SchedDangerButton: NSButton {
    init(_ title: String, action: Selector, target: AnyObject?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        bezelStyle = .rounded
        isBordered = true
        bezelColor = SchedDesign.takeover
        contentTintColor = .white
        controlSize = .regular
        font = SchedDesign.caption(12)
        appearance = SchedDesign.windowAppearance
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

// MARK: - Level pill

@MainActor
final class SchedLevelPill: NSView {
    private let textLabel = NSTextField(labelWithString: "")

    init(level: InterventionLevel) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = SchedDesign.levelColor(level).withAlphaComponent(0.18).cgColor
        textLabel.font = SchedDesign.caption(10)
        addSubview(textLabel)
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            textLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            textLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            textLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            textLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
        ])
        update(level: level)
    }

    func update(level: InterventionLevel) {
        textLabel.stringValue = level.label
        SchedDesign.label(textLabel, color: SchedDesign.levelColor(level))
        layer?.backgroundColor = SchedDesign.levelColor(level).withAlphaComponent(0.18).cgColor
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

// MARK: - Fading labels

@MainActor
final class SchedFadingLabel: NSTextField {
    private let fadeWidth: CGFloat = 26

    init(_ value: String) {
        super.init(frame: .zero)
        stringValue = value
        isBezeled = false
        drawsBackground = false
        isEditable = false
        isSelectable = false
        usesSingleLineMode = true
        lineBreakMode = .byClipping
        maximumNumberOfLines = 1
        wantsLayer = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        guard bounds.width > fadeWidth, let font else {
            layer?.mask = nil
            return
        }
        let required = (stringValue as NSString).size(withAttributes: [.font: font]).width
        guard required > bounds.width else {
            layer?.mask = nil
            return
        }

        let fade = CAGradientLayer()
        fade.frame = bounds
        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        let start = max(0, min(0.96, (bounds.width - fadeWidth) / bounds.width))
        fade.locations = [NSNumber(value: 0), NSNumber(value: Double(start)), NSNumber(value: 1)]
        fade.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
        layer?.mask = fade
    }
}

// MARK: - Alarm card (glass)

@MainActor
protocol SchedAlarmCardDelegate: AnyObject {
    func alarmCardSelected(_ id: UUID)
    func alarmCardEdit(_ id: UUID)
    func alarmCardMoveLater(_ id: UUID, minutes: Int)
    func alarmCardDuplicate(_ id: UUID)
    func alarmCardAddToCalendar(_ id: UUID)
    func alarmCardDisable(_ id: UUID)
    func alarmCardDelete(_ id: UUID)
}

@MainActor
final class SchedAlarmCard: NSControl {
    weak var cardDelegate: SchedAlarmCardDelegate?
    let alarmID: UUID
    private let glass: SchedGlassSurface
    private let timeLabel: NSTextField
    private let periodLabel: NSTextField
    private let titleLabel: SchedFadingLabel
    private let noteLabel: NSTextField
    private let actionIcon = NSImageView()
    private let stripe = NSView()
    private let levelPill: SchedLevelPill
    private var isSelected = false
    private var currentLevel: InterventionLevel

    init(alarm: SchedAlarm, selected: Bool) {
        alarmID = alarm.id
        currentLevel = alarm.level
        levelPill = SchedLevelPill(level: alarm.level)
        glass = SchedGlassSurface(
            cornerRadius: SchedDesign.cardRadius,
            tint: Self.cardTint(level: alarm.level, selected: selected),
            interactive: true
        )
        let timeParts = SchedTimeFormat.timeAndPeriod(from: alarm.fireAt)
        timeLabel = NSTextField(labelWithString: timeParts.time)
        timeLabel.font = SchedDesign.mono(22)
        SchedDesign.label(timeLabel)

        periodLabel = NSTextField(labelWithString: Self.contextText(for: alarm, period: timeParts.period))
        periodLabel.font = SchedDesign.caption(10)
        SchedDesign.label(periodLabel, color: SchedDesign.inkMuted)

        titleLabel = SchedFadingLabel(alarm.title)
        titleLabel.font = SchedDesign.title(16)
        titleLabel.toolTip = alarm.title
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        SchedDesign.label(titleLabel)

        noteLabel = NSTextField(wrappingLabelWithString: Self.noteText(alarm))
        noteLabel.font = SchedDesign.body(12)
        noteLabel.maximumNumberOfLines = 1
        noteLabel.lineBreakMode = .byTruncatingTail
        noteLabel.toolTip = alarm.note.isEmpty ? nil : alarm.note
        noteLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        SchedDesign.label(noteLabel, color: SchedDesign.inkMuted)

        super.init(frame: .zero)
        isSelected = selected
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 76).isActive = true
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityIdentifier(alarm.id.uuidString)
        setAccessibilityHelp("Open reminder details. Press Return again or double-click to edit.")
        updateAccessibility(alarm)

        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let inner = glass.innerContentView
        stripe.wantsLayer = true
        stripe.layer?.backgroundColor = SchedDesign.levelColor(alarm.level).cgColor
        stripe.layer?.cornerRadius = 2
        stripe.translatesAutoresizingMaskIntoConstraints = false

        [stripe, timeLabel, periodLabel, titleLabel, noteLabel].forEach { inner.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            stripe.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 12),
            stripe.topAnchor.constraint(equalTo: inner.topAnchor, constant: 14),
            stripe.bottomAnchor.constraint(equalTo: inner.bottomAnchor, constant: -14),
            stripe.widthAnchor.constraint(equalToConstant: 4),
            timeLabel.leadingAnchor.constraint(equalTo: stripe.trailingAnchor, constant: 14),
            timeLabel.topAnchor.constraint(equalTo: inner.topAnchor, constant: 16),
            periodLabel.leadingAnchor.constraint(equalTo: timeLabel.leadingAnchor),
            periodLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 0),
            titleLabel.leadingAnchor.constraint(equalTo: timeLabel.trailingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: timeLabel.topAnchor, constant: 2),
            noteLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            noteLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            noteLabel.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -16),
            noteLabel.bottomAnchor.constraint(lessThanOrEqualTo: inner.bottomAnchor, constant: -12),
        ])
        applySelection(selected)
    }

    func setSelected(_ on: Bool) {
        guard isSelected != on else { return }
        isSelected = on
        applySelection(on)
    }

    func refresh(alarm: SchedAlarm, selected: Bool) {
        let timeParts = SchedTimeFormat.timeAndPeriod(from: alarm.fireAt)
        timeLabel.stringValue = timeParts.time
        periodLabel.stringValue = Self.contextText(for: alarm, period: timeParts.period)
        titleLabel.stringValue = alarm.title
        titleLabel.toolTip = alarm.title
        titleLabel.needsLayout = true
        noteLabel.stringValue = Self.noteText(alarm)
        noteLabel.toolTip = alarm.note.isEmpty ? nil : alarm.note
        currentLevel = alarm.level
        stripe.layer?.backgroundColor = SchedDesign.levelColor(alarm.level).cgColor
        levelPill.update(level: alarm.level)
        isSelected = selected
        applySelection(selected)
        updateAccessibility(alarm)
    }

    private func applySelection(_ on: Bool) {
        glass.updateTint(Self.cardTint(level: currentLevel, selected: on), selected: on)
        layer?.borderWidth = on ? 2 : 0
        layer?.borderColor = on ? SchedDesign.accent.withAlphaComponent(0.55).cgColor : nil
        layer?.cornerRadius = SchedDesign.cardRadius
        alphaValue = 1
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            cardDelegate?.alarmCardEdit(alarmID)
        } else {
            cardDelegate?.alarmCardSelected(alarmID)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49: // Return or Space
            cardDelegate?.alarmCardSelected(alarmID)
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        cardDelegate?.alarmCardSelected(alarmID)
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(contextItem("Edit Reminder", symbol: "slider.horizontal.3", action: #selector(contextEdit)))
        menu.addItem(contextItem("Move 5 Minutes Later", symbol: "clock.arrow.circlepath", action: #selector(contextMoveLater)))
        menu.addItem(contextItem("Duplicate", symbol: "plus.square.on.square", action: #selector(contextDuplicate)))
        menu.addItem(contextItem("Add to Calendar…", symbol: "calendar.badge.plus", action: #selector(contextAddToCalendar)))
        menu.addItem(contextItem("Disable", symbol: "pause.circle", action: #selector(contextDisable)))
        menu.addItem(.separator())
        menu.addItem(contextItem("Delete", symbol: "trash", action: #selector(contextDelete)))
        return menu
    }

    private func contextItem(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }

    @objc private func contextEdit() { cardDelegate?.alarmCardEdit(alarmID) }
    @objc private func contextMoveLater() { cardDelegate?.alarmCardMoveLater(alarmID, minutes: 5) }
    @objc private func contextDuplicate() { cardDelegate?.alarmCardDuplicate(alarmID) }
    @objc private func contextAddToCalendar() { cardDelegate?.alarmCardAddToCalendar(alarmID) }
    @objc private func contextDisable() { cardDelegate?.alarmCardDisable(alarmID) }
    @objc private func contextDelete() { cardDelegate?.alarmCardDelete(alarmID) }

    private static func cardTint(level: InterventionLevel, selected: Bool) -> NSColor {
        let color = SchedDesign.levelColor(level)
        return color.withAlphaComponent(selected ? 0.28 : 0.13)
    }

    private static func noteText(_ alarm: SchedAlarm) -> String {
        if !alarm.note.isEmpty { return alarm.note }
        return alarm.repeatDaily ? "A recurring moment for future you." : "A one-time nudge with a clear next step."
    }

    private static func contextText(for alarm: SchedAlarm, period: String) -> String {
        let date = SchedTimeFormat.dateContext(from: alarm.fireAt)
        return period.isEmpty ? date : "\(date) · \(period)"
    }

    private func configureActionIcon(_ action: SchedAction) {
        let symbol: String
        let description: String
        let configured = !action.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch action {
        case .none:
            symbol = "bell"
            description = "Reminder only — no follow-up action"
        case .runShortcut:
            symbol = configured ? "command.circle.fill" : "exclamationmark.triangle.fill"
            description = configured ? "Runs Shortcut: \(action.payload)" : "Shortcut name is missing"
        case .openURL:
            symbol = configured ? "link.circle.fill" : "exclamationmark.triangle.fill"
            description = configured ? "Opens link" : "Link is missing"
        case .quitApp:
            symbol = configured ? "xmark.app.fill" : "exclamationmark.triangle.fill"
            description = configured ? "Quits \(action.payload)" : "App is missing"
        case .shell:
            symbol = "exclamationmark.triangle.fill"
            description = "Legacy action is disabled"
        }
        actionIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
        actionIcon.contentTintColor = action == .none ? SchedDesign.inkFaint : (configured ? SchedDesign.accent : .systemRed)
        actionIcon.toolTip = description
    }

    private func updateAccessibility(_ alarm: SchedAlarm) {
        let time = SchedTimeFormat.string(from: alarm.fireAt)
        let cadence = alarm.repeatDaily ? "Daily" : SchedTimeFormat.dateContext(from: alarm.fireAt)
        setAccessibilityLabel("\(alarm.title), \(cadence) at \(time), \(alarm.level.label)")
    }
}

// MARK: - Hero

@MainActor
final class SchedHeroStrip: NSView {
    private let glass: SchedGlassSurface
    private let detail = NSTextField(labelWithString: "—")
    private let countdown = NSTextField(labelWithString: "")

    init() {
        glass = SchedGlassSurface(cornerRadius: SchedDesign.cardRadius, tint: SchedDesign.bubbleAccent, interactive: false)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 72).isActive = true

        addSubview(glass)
        glass.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
        glass.layer?.borderColor = SchedDesign.line.withAlphaComponent(0.95).cgColor
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let inner = glass.innerContentView

        let headline = NSTextField(labelWithString: "Up next")
        headline.font = SchedDesign.section(10)
        SchedDesign.label(headline, color: SchedDesign.accent)
        detail.font = SchedDesign.title(18)
        detail.lineBreakMode = .byTruncatingTail
        detail.maximumNumberOfLines = 1
        SchedDesign.label(detail)
        countdown.font = SchedDesign.mono(26)
        SchedDesign.label(countdown, color: SchedDesign.accent)

        [headline, detail, countdown].forEach { inner.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            headline.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 20),
            headline.topAnchor.constraint(equalTo: inner.topAnchor, constant: 14),
            detail.leadingAnchor.constraint(equalTo: headline.leadingAnchor),
            detail.topAnchor.constraint(equalTo: headline.bottomAnchor, constant: 2),
            detail.trailingAnchor.constraint(lessThanOrEqualTo: countdown.leadingAnchor, constant: -18),
            countdown.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -20),
            countdown.centerYAnchor.constraint(equalTo: inner.centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    func refresh() {
        guard let next = ScheduleStore.shared.nextAlarm(), next.fireAt > .now else {
            detail.stringValue = "Your time is clear"
            countdown.stringValue = "Add one"
            return
        }
        detail.stringValue = next.title
        detail.toolTip = next.title
        let s = max(0, Int(next.fireAt.timeIntervalSinceNow))
        let h = s / 3600, m = (s % 3600) / 60
        countdown.stringValue = h > 0 ? String(format: "%dh %02dm", h, m) : String(format: "%dm", m)
    }
}

// MARK: - Nav

@MainActor
final class SchedNavItem: NSControl {
    let section: SchedSection
    private let icon = NSImageView()
    private let selection = NSView()

    init(section: SchedSection) {
        self.section = section
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: SchedDesign.navItemWidth).isActive = true
        heightAnchor.constraint(equalToConstant: SchedDesign.navItemHeight).isActive = true
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        selection.wantsLayer = true
        selection.layer?.cornerRadius = 2
        selection.layer?.backgroundColor = SchedDesign.accent.cgColor
        selection.isHidden = true

        icon.image = NSImage(systemSymbolName: section.icon, accessibilityDescription: nil)
        icon.contentTintColor = SchedDesign.inkMuted
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        toolTip = section.rawValue
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(section.rawValue)
        setAccessibilityIdentifier("navigation.\(section.rawValue.lowercased())")
        setAccessibilityHelp("Show \(section.shortLabel)")

        addSubview(selection)
        addSubview(icon)
        [selection, icon].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            selection.leadingAnchor.constraint(equalTo: leadingAnchor),
            selection.widthAnchor.constraint(equalToConstant: 3),
            selection.centerYAnchor.constraint(equalTo: centerYAnchor),
            selection.heightAnchor.constraint(equalToConstant: 24),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func setSelected(_ on: Bool) {
        selection.isHidden = !on
        icon.contentTintColor = on ? SchedDesign.accent : SchedDesign.inkMuted
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) { sendAction(action, to: target) }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 49: // Return or Space
            sendAction(action, to: target)
        default:
            super.keyDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        sendAction(action, to: target)
        return true
    }
}

enum SchedSection: String, CaseIterable {
    case schedule = "Schedule"
    case calendar = "Calendar"
    case timer = "Timer"
    case limits = "Limits"
    case ai = "AI"
    case settings = "Settings"

    var shortLabel: String {
        switch self {
        case .schedule: "Plan"
        case .calendar: "Calendar"
        case .timer: "Timer"
        case .limits: "Limits"
        case .ai: "AI"
        case .settings: "Prefs"
        }
    }

    var icon: String {
        switch self {
        case .schedule: "calendar.badge.clock"
        case .calendar: "calendar"
        case .timer: "timer"
        case .limits: "hourglass.badge.plus"
        case .ai: "sparkles.rectangle.stack"
        case .settings: "switch.2"
        }
    }
}

// MARK: - Form helpers

@MainActor
func schedFieldLabel(_ text: String) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = SchedDesign.body(12)
    SchedDesign.label(l, color: SchedDesign.inkMuted)
    return l
}

// MARK: - Scroll + form

@MainActor
func schedConfigureScroll(_ scroll: NSScrollView) {
    scroll.hasVerticalScroller = true
    scroll.hasHorizontalScroller = false
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.drawsBackground = false
    scroll.borderType = .noBorder
    scroll.translatesAutoresizingMaskIntoConstraints = false
}

@MainActor
func schedStyleSelector(_ control: NSControl) {
    control.appearance = SchedDesign.windowAppearance
    control.controlSize = .large
    control.font = SchedDesign.body(13)
    control.translatesAutoresizingMaskIntoConstraints = false
    control.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
}

@MainActor
final class SchedGlassField: NSView {
    let field: NSTextField
    private let glass: SchedGlassSurface

    init(placeholder: String = "") {
        glass = SchedGlassSurface(cornerRadius: 10, tint: SchedDesign.fieldTint, interactive: true)
        field = NSTextField()
        field.placeholderString = placeholder
        field.font = SchedDesign.body(13)
        field.textColor = SchedDesign.ink
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
        glass.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
        glass.layer?.borderColor = SchedDesign.line.withAlphaComponent(0.95).cgColor
        glass.innerContentView.addSubview(field)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 36),
            field.leadingAnchor.constraint(equalTo: glass.innerContentView.leadingAnchor, constant: 12),
            field.trailingAnchor.constraint(equalTo: glass.innerContentView.trailingAnchor, constant: -12),
            field.centerYAnchor.constraint(equalTo: glass.innerContentView.centerYAnchor),
            field.heightAnchor.constraint(greaterThanOrEqualToConstant: 20),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

@MainActor
final class SchedGlassTextView: NSView {
    let textView = NSTextView()
    private let glass: SchedGlassSurface

    init(placeholder: String = "", height: CGFloat = 76) {
        glass = SchedGlassSurface(cornerRadius: 10, tint: SchedDesign.fieldTint, interactive: true)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        textView.font = SchedDesign.body(13)
        textView.textColor = SchedDesign.ink
        textView.drawsBackground = false
        // Give multiline text a real vertical runway. The previous 4pt inset
        // combined with the enclosing clip view made the first baseline look
        // visibly cut off at some window scales.
        textView.textContainerInset = NSSize(width: 2, height: 8)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.toolTip = placeholder
        scroll.documentView = textView

        addSubview(glass)
        glass.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.78).cgColor
        glass.layer?.borderColor = SchedDesign.line.withAlphaComponent(0.95).cgColor
        glass.innerContentView.addSubview(scroll)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: height),
            scroll.leadingAnchor.constraint(equalTo: glass.innerContentView.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: glass.innerContentView.trailingAnchor, constant: -10),
            scroll.topAnchor.constraint(equalTo: glass.innerContentView.topAnchor, constant: 6),
            scroll.bottomAnchor.constraint(equalTo: glass.innerContentView.bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

@MainActor
func schedFormField(placeholder: String = "") -> NSTextField {
    let f = NSTextField()
    f.placeholderString = placeholder
    f.font = SchedDesign.body(13)
    f.textColor = SchedDesign.ink
    f.isBezeled = false
    f.isBordered = false
    f.drawsBackground = false
    f.focusRingType = .none
    f.translatesAutoresizingMaskIntoConstraints = false
    f.heightAnchor.constraint(equalToConstant: 36).isActive = true
    return f
}

@MainActor
func schedGlassField(placeholder: String = "") -> SchedGlassField {
    SchedGlassField(placeholder: placeholder)
}
