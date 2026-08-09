import AppKit
import Foundation

struct AppWatchRuntimeStatus: Equatable {
    let watchID: UUID
    let isRunning: Bool
    let elapsedSeconds: Int
    let limitSeconds: Int
    let didFire: Bool

    var remainingSeconds: Int { max(0, limitSeconds - elapsedSeconds) }

    var summary: String {
        guard isRunning else { return "Not running" }
        if didFire || elapsedSeconds >= limitSeconds {
            return "Limit reached · \(Self.duration(elapsedSeconds)) open"
        }
        return "Open \(Self.duration(elapsedSeconds)) · \(Self.duration(remainingSeconds)) left"
    }

    private static func duration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let rest = minutes % 60
            return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
        }
        if minutes > 0 { return "\(minutes)m \(remainder)s" }
        return "\(remainder)s"
    }
}

@MainActor
final class AppWatchMonitor {
    static let shared = AppWatchMonitor()

    private var timer: Timer?
    private var firstSeen: [UUID: Date] = [:]
    private var fired: Set<UUID> = []
    private var statuses: [UUID: AppWatchRuntimeStatus] = [:]
    private var observers: [UUID: () -> Void] = [:]

    private init() {}

    func start(pollInterval: TimeInterval = 2) {
        timer?.invalidate()
        let monitorTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        timer = monitorTimer
        RunLoop.main.add(monitorTimer, forMode: .common)
        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        firstSeen.removeAll()
        fired.removeAll()
        statuses.removeAll()
        notifyObservers()
    }

    func evaluateNow() {
        evaluate()
    }

    func status(for watchID: UUID) -> AppWatchRuntimeStatus? {
        statuses[watchID]
    }

    @discardableResult
    func observeChanges(_ observer: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = observer
        return id
    }

    func removeObserver(_ id: UUID) {
        observers.removeValue(forKey: id)
    }

    private func evaluate() {
        let selfBundle = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier != selfBundle }
        let enabledWatches = ScheduleStore.shared.store.appWatches.filter(\.enabled)
        let enabledIDs = Set(enabledWatches.map(\.id))

        firstSeen = firstSeen.filter { enabledIDs.contains($0.key) }
        fired = fired.intersection(enabledIDs)

        var nextStatuses: [UUID: AppWatchRuntimeStatus] = [:]

        for watch in ScheduleStore.shared.store.appWatches {
            guard watch.enabled else {
                nextStatuses[watch.id] = AppWatchRuntimeStatus(
                    watchID: watch.id,
                    isRunning: false,
                    elapsedSeconds: 0,
                    limitSeconds: watch.maxMinutes * 60,
                    didFire: false
                )
                continue
            }

            guard let app = running.first(where: { candidate in
                watch.matches(
                    appName: candidate.localizedName ?? candidate.executableURL?.lastPathComponent ?? "",
                    bundleId: candidate.bundleIdentifier,
                    executablePath: candidate.executableURL?.path
                )
            }) else {
                firstSeen.removeValue(forKey: watch.id)
                fired.remove(watch.id)
                nextStatuses[watch.id] = AppWatchRuntimeStatus(
                    watchID: watch.id,
                    isRunning: false,
                    elapsedSeconds: 0,
                    limitSeconds: watch.maxMinutes * 60,
                    didFire: false
                )
                continue
            }

            let started = firstSeen[watch.id] ?? app.launchDate ?? .now
            firstSeen[watch.id] = started
            let elapsed = max(0, Int(Date().timeIntervalSince(started)))
            let reached = elapsed >= watch.maxMinutes * 60

            if reached, fired.insert(watch.id).inserted {
                let name = app.localizedName ?? watch.appName
                Scheduler.shared.fireNow(watch.interventionAlarm(frontName: name))
            }

            nextStatuses[watch.id] = AppWatchRuntimeStatus(
                watchID: watch.id,
                isRunning: true,
                elapsedSeconds: elapsed,
                limitSeconds: watch.maxMinutes * 60,
                didFire: fired.contains(watch.id)
            )
        }

        statuses = nextStatuses
        notifyObservers()
    }

    private func notifyObservers() {
        for observer in observers.values { observer() }
    }
}
