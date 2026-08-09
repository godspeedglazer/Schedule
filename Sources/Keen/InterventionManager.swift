import AppKit

/// Tracks every intervention window so dismiss always releases the screen.
@MainActor
final class InterventionManager {
    static let shared = InterventionManager()

    private var controllers: [ObjectIdentifier: InterventionWindowController] = [:]

    private init() {}

    func register(_ controller: InterventionWindowController) {
        controllers[ObjectIdentifier(controller)] = controller
    }

    func unregister(_ controller: InterventionWindowController) {
        controllers.removeValue(forKey: ObjectIdentifier(controller))
    }

    func dismiss(alarmID: UUID) {
        let matching = controllers.values.filter { $0.alarmID == alarmID }
        for controller in matching {
            controller.forceDismiss()
        }
    }

    func dismissAll() {
        for controller in Array(controllers.values) {
            controller.forceDismiss()
        }
        controllers.removeAll()
    }

    var hasActive: Bool { !controllers.isEmpty }
}
