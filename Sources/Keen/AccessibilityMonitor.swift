import AppKit
import CoreGraphics
import Foundation

/// System idle time via CGEventSource — does not require Accessibility permission.
@MainActor
final class AccessibilityMonitor {
    static let shared = AccessibilityMonitor()

    private var timer: Timer?
    var onIdleThreshold: ((TimeInterval) -> Void)?

    private init() {}

    func start(pollInterval: TimeInterval = 30) {
        timer?.invalidate()
        timer = nil
        guard ScheduleStore.shared.store.idleMinutesBeforeNudge != nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateIdle() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func secondsSinceUserInput() -> TimeInterval {
        let types: [CGEventType] = [.mouseMoved, .leftMouseDown, .rightMouseDown, .keyDown, .scrollWheel]
        let idleDurations = types.map { type in
            CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: type)
        }
        return idleDurations.min() ?? 0
    }

    func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func evaluateIdle() {
        guard let minutes = ScheduleStore.shared.store.idleMinutesBeforeNudge else {
            stop()
            return
        }
        let idle = secondsSinceUserInput()
        if idle >= TimeInterval(minutes * 60) {
            onIdleThreshold?(idle)
        }
    }
}
