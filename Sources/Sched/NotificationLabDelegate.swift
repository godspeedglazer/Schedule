import AppKit

/// A deliberately tiny, separate harness for refining reminder interventions.
/// It uses Sched's production intervention windows, so every button tests the
/// real gesture, animation, audio, and dismissal lifecycle.
@MainActor
final class NotificationLabDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = NSTextField(labelWithString: "Sched Notification Lab")
        title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)
        title.textColor = .labelColor

        let copy = NSTextField(wrappingLabelWithString: "Three seeded production reminders. Click, inspect, dismiss, repeat.")
        copy.font = NSFont.systemFont(ofSize: 13)
        copy.textColor = .secondaryLabelColor
        copy.maximumNumberOfLines = 2

        let gentle = button("Corner message", action: #selector(showCorner))
        let banner = button("Side banner", action: #selector(showBanner))
        let takeover = button("Full screen", action: #selector(showTakeover))
        let controls = NSStackView(views: [gentle, banner, takeover])
        controls.orientation = .horizontal
        controls.distribution = .fillEqually
        controls.spacing = 10

        let pane = NSView()
        pane.wantsLayer = true
        pane.layer?.cornerRadius = 14
        pane.layer?.cornerCurve = .continuous
        pane.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        pane.layer?.borderWidth = 1
        pane.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.45).cgColor
        let status = NSTextField(labelWithString: "These are production notification surfaces, not previews.")
        status.font = NSFont.systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        pane.addSubview(status)
        status.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: pane.leadingAnchor, constant: 14),
            status.trailingAnchor.constraint(equalTo: pane.trailingAnchor, constant: -14),
            status.centerYAnchor.constraint(equalTo: pane.centerYAnchor),
        ])

        [title, copy, controls, pane].forEach { content.addSubview($0); $0.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 22),
            title.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -22),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            copy.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            copy.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            copy.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            controls.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            controls.topAnchor.constraint(equalTo: copy.bottomAnchor, constant: 22),
            controls.heightAnchor.constraint(equalToConstant: 38),
            pane.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            pane.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 18),
            pane.heightAnchor.constraint(equalToConstant: 48),
            pane.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22),
        ])

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 218),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Sched Notification Lab"
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.controlSize = .large
        return button
    }

    @objc private func showCorner() { show(level: .gentle, title: "Finish the release notes.", note: "A message from earlier you.") }
    @objc private func showBanner() { show(level: .focus, title: "Leave for enrollment.", note: "") }
    @objc private func showTakeover() { show(level: .takeover, title: "Focus block", note: "Timer complete. Take a breath before the next thing.") }

    private func show(level: InterventionLevel, title: String, note: String) {
        let alarm = SchedAlarm(title: title, note: note, fireAt: .now, level: level)
        _ = InterventionWindowController(alarm: alarm) { }
    }
}
