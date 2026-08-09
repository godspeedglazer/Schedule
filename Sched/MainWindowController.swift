import AppKit

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MainWindowController()

    private let contentHost = NSView()
    private var navItems: [SchedSection: SchedNavItem] = [:]
    private var panels: [SchedSection: NSViewController] = [:]
    private var panelConstraints: [NSLayoutConstraint] = []
    private var activeSection: SchedSection?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.minSize = NSSize(width: 780, height: 560)
        window.collectionBehavior.insert(.fullScreenNone)
        let restoredFrame = window.setFrameUsingName("Sched.MainWindow")
        _ = window.setFrameAutosaveName("Sched.MainWindow")
        if !restoredFrame {
            window.center()
        }
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = SchedDesign.canvas
        super.init(window: window)
        window.delegate = self
        buildChrome()
        showSection(.schedule)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    func showWindow() {
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func showAlarm(_ id: UUID) {
        showSection(.schedule)
        if let schedule = panel(for: .schedule) as? SchedulePanelController {
            schedule.selectAlarm(id)
        }
        showWindow()
    }

    func showSection(_ section: SchedSection) {
        guard activeSection != section else { return }
        activeSection = section
        for (key, item) in navItems { item.setSelected(key == section) }

        NSLayoutConstraint.deactivate(panelConstraints)
        panelConstraints.removeAll()
        panels.values.forEach { $0.view.removeFromSuperview() }

        let panel = panel(for: section)
        panel.view.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(panel.view)
        panelConstraints = [
            panel.view.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor),
            panel.view.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor),
            panel.view.topAnchor.constraint(equalTo: contentHost.topAnchor),
            panel.view.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor),
        ]
        NSLayoutConstraint.activate(panelConstraints)
    }

    private func panel(for section: SchedSection) -> NSViewController {
        if let existing = panels[section] { return existing }
        let vc: NSViewController
        switch section {
        case .schedule: vc = SchedulePanelController()
        case .calendar: vc = CalendarPanelController()
        case .timer: vc = TimerPanelController()
        case .limits: vc = SettingsPanelController(mode: .limits)
        case .settings: vc = SettingsPanelController(mode: .preferences)
        }
        panels[section] = vc
        return vc
    }

    private func buildChrome() {
        guard let content = window?.contentView else { return }
        let root = SchedCanvasView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let railGlass = SchedGlassSurface(
            cornerRadius: SchedDesign.railCorner,
            tint: NSColor.white.withAlphaComponent(0.14)
        )
        let railStack = NSStackView()
        railStack.orientation = .vertical
        railStack.spacing = 4
        railStack.alignment = .centerX
        railStack.translatesAutoresizingMaskIntoConstraints = false

        for section in SchedSection.allCases {
            let item = SchedNavItem(section: section)
            item.target = self
            item.action = #selector(navTap(_:))
            navItems[section] = item
            railStack.addArrangedSubview(item)
        }

        let railSpacer = NSView()
        railSpacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        railSpacer.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        railStack.addArrangedSubview(railSpacer)
        railStack.addArrangedSubview(makeRailMark())

        let inner = railGlass.innerContentView
        inner.addSubview(railStack)
        NSLayoutConstraint.activate([
            railStack.topAnchor.constraint(equalTo: inner.topAnchor, constant: 12),
            railStack.bottomAnchor.constraint(equalTo: inner.bottomAnchor, constant: -12),
            railStack.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 8),
            railStack.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -8),
        ])

        contentHost.translatesAutoresizingMaskIntoConstraints = false
        railGlass.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(railGlass)
        root.addSubview(contentHost)

        NSLayoutConstraint.activate([
            railGlass.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            railGlass.topAnchor.constraint(equalTo: root.topAnchor, constant: 42),
            railGlass.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            railGlass.widthAnchor.constraint(equalToConstant: SchedDesign.railWidth),
            contentHost.leadingAnchor.constraint(equalTo: railGlass.trailingAnchor, constant: SchedDesign.contentGap),
            contentHost.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -SchedDesign.contentGap),
            contentHost.topAnchor.constraint(equalTo: root.topAnchor, constant: 42),
            contentHost.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -SchedDesign.contentGap),
        ])
    }


    private func makeRailMark() -> NSView {
        let image: NSImage
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "svg"),
           let bundledImage = NSImage(contentsOf: url) {
            image = bundledImage
        } else {
            image = NSImage(systemSymbolName: "calendar.badge.clock", accessibilityDescription: "Sched") ?? NSImage()
        }

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.toolTip = "Sched"
        imageView.setAccessibilityLabel("Sched")
        imageView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 30),
            imageView.heightAnchor.constraint(equalToConstant: 30),
        ])
        return imageView
    }

    @objc private func navTap(_ sender: SchedNavItem) {
        showSection(sender.section)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if ScheduleStore.shared.store.headlessWhenClosed {
            sender.orderOut(nil)
            return false
        }
        return true
    }
}
