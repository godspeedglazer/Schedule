import AppKit
import Foundation

@MainActor
final class AppWatchMonitor {
    static let shared = AppWatchMonitor()

    private var timer: Timer?
    private var firstSeen: [UUID: Date] = [:]
    private var fired: Set<UUID> = []

    private init() {}

    func start(pollInterval: TimeInterval = 2) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        evaluate()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        firstSeen.removeAll()
        fired.removeAll()
    }

    private func evaluate() {
        let selfBundle = Bundle.main.bundleIdentifier
        let running = NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier != selfBundle }
        let enabledWatches = ScheduleStore.shared.store.appWatches.filter(\.enabled)
        let enabledIDs = Set(enabledWatches.map(\.id))

        firstSeen = firstSeen.filter { enabledIDs.contains($0.key) }
        fired = fired.intersection(enabledIDs)

        for watch in enabledWatches {
            guard let app = running.first(where: { candidate in
                watch.matches(
                    appName: candidate.localizedName ?? candidate.executableURL?.lastPathComponent ?? "",
                    bundleId: candidate.bundleIdentifier,
                    executablePath: candidate.executableURL?.path
                )
            }) else {
                firstSeen.removeValue(forKey: watch.id)
                fired.remove(watch.id)
                continue
            }

            let started = firstSeen[watch.id] ?? app.launchDate ?? .now
            firstSeen[watch.id] = started
            guard Date().timeIntervalSince(started) >= TimeInterval(watch.maxMinutes * 60) else { continue }
            guard fired.insert(watch.id).inserted else { continue }

            let name = app.localizedName ?? watch.appName
            Scheduler.shared.fireNow(watch.interventionAlarm(frontName: name))
        }
    }
}
