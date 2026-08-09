import AppKit

/// Owns the app's Dock/background presence independently of any particular view.
/// Sched can therefore keep scheduling in the background even when every visible
/// surface (window and status items) is disabled.
@MainActor
final class AppPresenceController {
    static let shared = AppPresenceController()

    private var storeObserver: UUID?
    private var mainWindowVisible = false

    private init() {}

    func start(mainWindowVisible: Bool) {
        self.mainWindowVisible = mainWindowVisible
        if storeObserver == nil {
            storeObserver = ScheduleStore.shared.observeChanges { [weak self] in
                self?.applyCurrentPolicy()
            }
        }
        applyCurrentPolicy()
    }

    func mainWindowWillShow() {
        mainWindowVisible = true
        applyCurrentPolicy()
    }

    func mainWindowDidHide() {
        mainWindowVisible = false
        applyCurrentPolicy()
    }

    func applyCurrentPolicy() {
        let preference = ScheduleStore.shared.store.dockPresence
        let policy: NSApplication.ActivationPolicy
        switch preference {
        case .always:
            policy = .regular
        case .whileWindowOpen:
            policy = mainWindowVisible ? .regular : .accessory
        case .never:
            policy = .accessory
        }
        NSApp.setActivationPolicy(policy)
    }
}
