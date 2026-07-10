import AppKit

@MainActor
final class MainWindowController: NSWindowController, NSWindowDelegate {
    static let shared = MainWindowController()

    private let contentHost = NSView()
    private var navItems: [KeenSection: KeenNavItem] = [:]
    private var panels: [KeenSection: NSViewController] = [:]
    private var panelConstraints: [NSLayoutConstraint] = []
    private var activeSection: KeenSection?

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.minSize = NSSize(width: 820, height: 620)
        window.maxSize = NSSize(width: 820, height: 620)
        window.collectionBehavior.insert(.fullScreenNone)
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.center()
        window.isReleasedWhenClosed = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = KeenDesign.canvas
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

    func showSection(_ section: KeenSection) {
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

    private func panel(for section: KeenSection) -> NSViewController {
        if let existing = panels[section] { return existing }
        let vc: NSViewController
        switch section {
        case .schedule: vc = SchedulePanelController()
        case .calendar: vc = CalendarPanelController()
        case .timer: vc = TimerPanelController()
        case .settings: vc = SettingsPanelController()
        }
        panels[section] = vc
        return vc
    }

    private func buildChrome() {
        guard let content = window?.contentView else { return }
        let root = KeenCanvasView()
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let railGlass = KeenGlassSurface(
            cornerRadius: KeenDesign.railCorner,
            tint: NSColor.white.withAlphaComponent(0.14)
        )
        let railStack = NSStackView()
        railStack.orientation = .vertical
        railStack.spacing = 4
        railStack.alignment = .centerX
        railStack.translatesAutoresizingMaskIntoConstraints = false

        for section in KeenSection.allCases {
            let item = KeenNavItem(section: section)
            item.target = self
            item.action = #selector(navTap(_:))
            navItems[section] = item
            railStack.addArrangedSubview(item)
        }

        let inner = railGlass.innerContentView
        inner.addSubview(railStack)
        NSLayoutConstraint.activate([
            railStack.topAnchor.constraint(equalTo: inner.topAnchor, constant: 12),
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
            railGlass.widthAnchor.constraint(equalToConstant: KeenDesign.railWidth),
            contentHost.leadingAnchor.constraint(equalTo: railGlass.trailingAnchor, constant: KeenDesign.contentGap),
            contentHost.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -KeenDesign.contentGap),
            contentHost.topAnchor.constraint(equalTo: root.topAnchor, constant: 42),
            contentHost.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -KeenDesign.contentGap),
        ])
    }

    @objc private func navTap(_ sender: KeenNavItem) {
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
