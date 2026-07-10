import AppKit

@MainActor
final class KeenCanvasView: NSView {
    private let gradient = CAGradientLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        gradient.colors = [KeenDesign.canvas.cgColor, KeenDesign.canvasDeep.cgColor]
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
final class KeenFlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
final class KeenGlassSurface: NSView {
    private let content = NSView()
    private var glassView: NSView?
    private var cornerRadius: CGFloat
    private var interactive: Bool
    private let stableWhenInactive: Bool
    private var currentTint: NSColor?

    var innerContentView: NSView { content }

    init(
        cornerRadius: CGFloat = KeenDesign.cardRadius,
        tint: NSColor? = nil,
        interactive: Bool = false,
        stableWhenInactive: Bool = true
    ) {
        self.cornerRadius = cornerRadius
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
                glass.effectIsInteractive = false
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
final class KeenGlassContainer: NSView {
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
final class KeenPrimaryButton: NSButton {
    init(_ title: String, action: Selector, target: AnyObject?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        bezelStyle = .rounded
        isBordered = true
        bezelColor = KeenDesign.accent
        contentTintColor = .white
        controlSize = .large
        font = KeenDesign.caption(12)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 36).isActive = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

@MainActor
final class KeenGhostButton: NSButton {
    init(_ title: String, action: Selector, target: AnyObject?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        bezelStyle = .rounded
        isBordered = true
        controlSize = .regular
        contentTintColor = KeenDesign.inkMuted
        font = KeenDesign.caption(12)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

@MainActor
final class KeenDangerButton: NSButton {
    init(_ title: String, action: Selector, target: AnyObject?) {
        super.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        bezelStyle = .rounded
        isBordered = true
        bezelColor = KeenDesign.takeover
        contentTintColor = .white
        controlSize = .regular
        font = KeenDesign.caption(12)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 30).isActive = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

// MARK: - Level pill

@MainActor
final class KeenLevelPill: NSView {
    private let textLabel = NSTextField(labelWithString: "")

    init(level: InterventionLevel) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = KeenDesign.levelColor(level).withAlphaComponent(0.18).cgColor
        textLabel.font = KeenDesign.caption(10)
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
        KeenDesign.label(textLabel, color: KeenDesign.levelColor(level))
        layer?.backgroundColor = KeenDesign.levelColor(level).withAlphaComponent(0.18).cgColor
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

// MARK: - Alarm card (glass)

@MainActor
protocol KeenAlarmCardDelegate: AnyObject {
    func alarmCardSelected(_ id: UUID)
}

@MainActor
final class KeenAlarmCard: NSControl {
    weak var cardDelegate: KeenAlarmCardDelegate?
    let alarmID: UUID
    private let glass: KeenGlassSurface
    private let timeLabel: NSTextField
    private let periodLabel: NSTextField
    private let titleLabel: NSTextField
    private let noteLabel: NSTextField
    private let actionIcon = NSImageView()
    private let stripe = NSView()
    private let levelPill: KeenLevelPill
    private var isSelected = false
    private var currentLevel: InterventionLevel

    init(alarm: KeenAlarm, selected: Bool) {
        alarmID = alarm.id
        currentLevel = alarm.level
        levelPill = KeenLevelPill(level: alarm.level)
        glass = KeenGlassSurface(
            cornerRadius: KeenDesign.cardRadius,
            tint: Self.cardTint(level: alarm.level, selected: selected),
            interactive: true
        )
        let timeParts = SchedTimeFormat.timeAndPeriod(from: alarm.fireAt)
        timeLabel = NSTextField(labelWithString: timeParts.time)
        timeLabel.font = KeenDesign.mono(22)
        KeenDesign.label(timeLabel)

        periodLabel = NSTextField(labelWithString: Self.contextText(for: alarm, period: timeParts.period))
        periodLabel.font = KeenDesign.caption(10)
        KeenDesign.label(periodLabel, color: KeenDesign.inkMuted)

        titleLabel = NSTextField(labelWithString: alarm.title)
        titleLabel.font = KeenDesign.title(16)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        titleLabel.toolTip = alarm.title
        KeenDesign.label(titleLabel)

        noteLabel = NSTextField(labelWithString: Self.noteText(alarm))
        noteLabel.font = KeenDesign.body(12)
        KeenDesign.label(noteLabel, color: KeenDesign.inkMuted)
        noteLabel.lineBreakMode = .byTruncatingTail

        super.init(frame: .zero)
        isSelected = selected
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 76).isActive = true
        wantsLayer = true

        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let inner = glass.innerContentView
        stripe.wantsLayer = true
        stripe.layer?.backgroundColor = KeenDesign.levelColor(alarm.level).cgColor
        stripe.layer?.cornerRadius = 2
        stripe.translatesAutoresizingMaskIntoConstraints = false

        [stripe, timeLabel, periodLabel, titleLabel, noteLabel, actionIcon, levelPill].forEach { inner.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        configureActionIcon(alarm.action)
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
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionIcon.leadingAnchor, constant: -10),
            titleLabel.topAnchor.constraint(equalTo: timeLabel.topAnchor, constant: 2),
            noteLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            noteLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 3),
            noteLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            actionIcon.trailingAnchor.constraint(equalTo: levelPill.leadingAnchor, constant: -10),
            actionIcon.centerYAnchor.constraint(equalTo: inner.centerYAnchor),
            actionIcon.widthAnchor.constraint(equalToConstant: 16),
            actionIcon.heightAnchor.constraint(equalToConstant: 16),
            levelPill.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -16),
            levelPill.centerYAnchor.constraint(equalTo: inner.centerYAnchor),
        ])
        applySelection(selected)
    }

    func setSelected(_ on: Bool) {
        guard isSelected != on else { return }
        isSelected = on
        applySelection(on)
    }

    func refresh(alarm: KeenAlarm, selected: Bool) {
        let timeParts = SchedTimeFormat.timeAndPeriod(from: alarm.fireAt)
        timeLabel.stringValue = timeParts.time
        periodLabel.stringValue = Self.contextText(for: alarm, period: timeParts.period)
        titleLabel.stringValue = alarm.title
        titleLabel.toolTip = alarm.title
        noteLabel.stringValue = Self.noteText(alarm)
        noteLabel.toolTip = alarm.note.isEmpty ? nil : alarm.note
        configureActionIcon(alarm.action)
        currentLevel = alarm.level
        stripe.layer?.backgroundColor = KeenDesign.levelColor(alarm.level).cgColor
        levelPill.update(level: alarm.level)
        isSelected = selected
        applySelection(selected)
    }

    private func applySelection(_ on: Bool) {
        glass.updateTint(Self.cardTint(level: currentLevel, selected: on), selected: on)
        layer?.borderWidth = on ? 2 : 0
        layer?.borderColor = on ? KeenDesign.accent.withAlphaComponent(0.55).cgColor : nil
        layer?.cornerRadius = KeenDesign.cardRadius
        alphaValue = 1
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) { cardDelegate?.alarmCardSelected(alarmID) }

    private static func cardTint(level: InterventionLevel, selected: Bool) -> NSColor {
        let color = KeenDesign.levelColor(level)
        return color.withAlphaComponent(selected ? 0.28 : 0.13)
    }

    private static func noteText(_ alarm: KeenAlarm) -> String {
        if !alarm.note.isEmpty { return alarm.note }
        return alarm.repeatDaily ? "A recurring moment for future you." : "A one-time nudge with a clear next step."
    }

    private static func contextText(for alarm: KeenAlarm, period: String) -> String {
        let date = SchedTimeFormat.dateContext(from: alarm.fireAt)
        return period.isEmpty ? date : "\(date) · \(period)"
    }

    private func configureActionIcon(_ action: KeenAction) {
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
        actionIcon.contentTintColor = action == .none ? KeenDesign.inkFaint : (configured ? KeenDesign.accent : .systemRed)
        actionIcon.toolTip = description
    }
}

// MARK: - Hero

@MainActor
final class KeenHeroStrip: NSView {
    private let glass: KeenGlassSurface
    private let detail = NSTextField(labelWithString: "—")
    private let countdown = NSTextField(labelWithString: "")

    init() {
        glass = KeenGlassSurface(cornerRadius: KeenDesign.cardRadius, tint: KeenDesign.bubbleAccent, interactive: false)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 72).isActive = true

        addSubview(glass)
        NSLayoutConstraint.activate([
            glass.leadingAnchor.constraint(equalTo: leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: trailingAnchor),
            glass.topAnchor.constraint(equalTo: topAnchor),
            glass.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        let inner = glass.innerContentView

        let headline = NSTextField(labelWithString: "Up next")
        headline.font = KeenDesign.section(10)
        KeenDesign.label(headline, color: KeenDesign.accent)
        detail.font = KeenDesign.title(18)
        detail.lineBreakMode = .byTruncatingTail
        detail.maximumNumberOfLines = 1
        KeenDesign.label(detail)
        countdown.font = KeenDesign.mono(26)
        KeenDesign.label(countdown, color: KeenDesign.accent)

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
final class KeenNavItem: NSControl {
    let section: KeenSection
    private let icon = NSImageView()
    private let selection = NSView()

    init(section: KeenSection) {
        self.section = section
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: KeenDesign.navItemWidth).isActive = true
        heightAnchor.constraint(equalToConstant: KeenDesign.navItemHeight).isActive = true
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .vertical)

        selection.wantsLayer = true
        selection.layer?.cornerRadius = 2
        selection.layer?.backgroundColor = KeenDesign.accent.cgColor
        selection.isHidden = true

        icon.image = NSImage(systemSymbolName: section.icon, accessibilityDescription: nil)
        icon.contentTintColor = KeenDesign.inkMuted
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        toolTip = section.rawValue
        setAccessibilityLabel(section.rawValue)

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
        icon.contentTintColor = on ? KeenDesign.accent : KeenDesign.inkMuted
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }

    override func mouseDown(with event: NSEvent) { sendAction(action, to: target) }
}

enum KeenSection: String, CaseIterable {
    case schedule = "Schedule"
    case calendar = "Calendar"
    case timer = "Timer"
    case limits = "Limits"
    case settings = "Settings"

    var shortLabel: String {
        switch self {
        case .schedule: "Plan"
        case .calendar: "Calendar"
        case .timer: "Timer"
        case .limits: "Limits"
        case .settings: "Prefs"
        }
    }

    var icon: String {
        switch self {
        case .schedule: "calendar.badge.clock"
        case .calendar: "calendar"
        case .timer: "timer"
        case .limits: "hourglass.badge.plus"
        case .settings: "switch.2"
        }
    }
}

// MARK: - Form helpers

@MainActor
func keenFieldLabel(_ text: String) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = KeenDesign.body(12)
    KeenDesign.label(l, color: KeenDesign.inkMuted)
    return l
}

// MARK: - Scroll + form

@MainActor
func schedConfigureScroll(_ scroll: NSScrollView) {
    scroll.hasVerticalScroller = false
    scroll.hasHorizontalScroller = false
    scroll.autohidesScrollers = true
    scroll.scrollerStyle = .overlay
    scroll.drawsBackground = false
    scroll.borderType = .noBorder
    scroll.translatesAutoresizingMaskIntoConstraints = false
}

@MainActor
func schedStyleSelector(_ control: NSControl) {
    control.controlSize = .large
    control.font = KeenDesign.body(13)
    control.translatesAutoresizingMaskIntoConstraints = false
    control.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
}

@MainActor
final class KeenGlassField: NSView {
    let field: NSTextField
    private let glass: KeenGlassSurface

    init(placeholder: String = "") {
        glass = KeenGlassSurface(cornerRadius: 10, tint: KeenDesign.fieldTint, interactive: true)
        field = NSTextField()
        field.placeholderString = placeholder
        field.font = KeenDesign.body(13)
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        addSubview(glass)
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
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

@MainActor
func keenFormField(placeholder: String = "") -> NSTextField {
    let f = NSTextField()
    f.placeholderString = placeholder
    f.font = KeenDesign.body(13)
    f.isBezeled = false
    f.isBordered = false
    f.drawsBackground = false
    f.focusRingType = .none
    f.translatesAutoresizingMaskIntoConstraints = false
    f.heightAnchor.constraint(equalToConstant: 36).isActive = true
    return f
}

@MainActor
func keenGlassField(placeholder: String = "") -> KeenGlassField {
    KeenGlassField(placeholder: placeholder)
}

// MARK: - Gentle toast (interventions)

@MainActor
final class KeenGentleToast: NSView {
    private let actionTarget: KeenToastTarget

    init(
        title: String,
        note: String,
        onDone: @escaping () -> Void,
        onSnooze: @escaping (Int) -> Void,
        onAction: (() -> Void)? = nil
    ) {
        actionTarget = KeenToastTarget(done: onDone, snooze: onSnooze, run: onAction)
        super.init(frame: .zero)
        let glass = KeenGlassSurface(
            cornerRadius: 18,
            tint: KeenDesign.levelColor(.gentle).withAlphaComponent(0.16),
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
        let inner = glass.innerContentView

        let stripe = NSView()
        stripe.wantsLayer = true
        stripe.layer?.backgroundColor = KeenDesign.levelColor(.gentle).cgColor
        stripe.layer?.cornerRadius = 2

        let symbol = NSImageView(image: NSImage(systemSymbolName: "bell.badge.fill", accessibilityDescription: "Reminder") ?? NSImage())
        symbol.contentTintColor = KeenDesign.accent
        symbol.toolTip = "Drag the card to move it"

        let eyebrow = NSTextField(labelWithString: "REMINDER  ·  \(SchedTimeFormat.string(from: .now))")
        eyebrow.font = KeenDesign.section(10)
        KeenDesign.label(eyebrow, color: KeenDesign.accent)

        let t = NSTextField(labelWithString: title)
        t.font = KeenDesign.title(16)
        KeenDesign.label(t)
        let n = NSTextField(wrappingLabelWithString: note.isEmpty ? "Time to switch." : note)
        n.font = KeenDesign.body(12)
        KeenDesign.label(n, color: KeenDesign.inkMuted)
        n.maximumNumberOfLines = 2

        let done = KeenPrimaryButton("Done", action: #selector(KeenToastTarget.done), target: actionTarget)
        let snooze = KeenSnoozeButton(
            defaultMinutes: ScheduleStore.shared.store.snoozeMinutes,
            action: onSnooze
        )
        var buttons: [NSView] = [snooze]
        if onAction != nil {
            buttons.append(KeenGhostButton("Run action", action: #selector(KeenToastTarget.run), target: actionTarget))
        }
        buttons.append(done)
        let buttonRow = NSStackView(views: buttons)
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        [stripe, symbol, eyebrow, t, n, buttonRow].forEach { inner.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            stripe.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 10),
            stripe.topAnchor.constraint(equalTo: inner.topAnchor, constant: 16),
            stripe.bottomAnchor.constraint(equalTo: inner.bottomAnchor, constant: -16),
            stripe.widthAnchor.constraint(equalToConstant: 4),
            eyebrow.leadingAnchor.constraint(equalTo: stripe.trailingAnchor, constant: 14),
            eyebrow.topAnchor.constraint(equalTo: inner.topAnchor, constant: 14),
            symbol.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -18),
            symbol.topAnchor.constraint(equalTo: inner.topAnchor, constant: 14),
            symbol.widthAnchor.constraint(equalToConstant: 20),
            symbol.heightAnchor.constraint(equalToConstant: 20),
            t.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 18),
            t.topAnchor.constraint(equalTo: eyebrow.bottomAnchor, constant: 3),
            t.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -18),
            n.leadingAnchor.constraint(equalTo: t.leadingAnchor),
            n.topAnchor.constraint(equalTo: t.bottomAnchor, constant: 2),
            n.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -18),
            n.bottomAnchor.constraint(lessThanOrEqualTo: buttonRow.topAnchor, constant: -8),
            buttonRow.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -16),
            buttonRow.bottomAnchor.constraint(equalTo: inner.bottomAnchor, constant: -14),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}

@MainActor
final class KeenToastTarget: NSObject {
    private let doneHandler: () -> Void
    private let runHandler: (() -> Void)?

    init(done: @escaping () -> Void, snooze: @escaping (Int) -> Void, run: (() -> Void)?) {
        doneHandler = done
        runHandler = run
    }

    @objc func done() { doneHandler() }
    @objc func run() { runHandler?() }
}

@MainActor
final class KeenSnoozeButton: NSPopUpButton {
    private let handler: (Int) -> Void

    init(defaultMinutes: Int, action: @escaping (Int) -> Void) {
        handler = action
        super.init(frame: .zero, pullsDown: false)
        bezelStyle = .rounded
        controlSize = .large
        font = KeenDesign.caption(12)
        focusRingType = .none
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 34).isActive = true
        widthAnchor.constraint(greaterThanOrEqualToConstant: 116).isActive = true

        addItem(withTitle: "Snooze…")
        let options = Array(Set([defaultMinutes, 5, 10, 15, 30, 60])).sorted()
        for minutes in options {
            let item = NSMenuItem(title: "\(minutes) minutes", action: nil, keyEquivalent: "")
            item.representedObject = minutes
            menu?.addItem(item)
        }
        selectItem(at: 0)
        target = self
        self.action = #selector(didChooseDuration)
    }

    @objc private func didChooseDuration() {
        guard let minutes = selectedItem?.representedObject as? Int else { return }
        selectItem(at: 0)
        handler(minutes)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { nil }
}
