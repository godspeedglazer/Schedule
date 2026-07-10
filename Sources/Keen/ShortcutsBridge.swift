import AppKit
import Foundation

@MainActor
enum ShortcutsBridge {
    static func runShortcut(named name: String) {
        guard !name.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        try? process.run()
    }

    static func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    static func quitApp(named name: String, bundleId: String? = nil) {
        if let bundleId, !bundleId.isEmpty {
            RunningApps.quit(bundleId: bundleId)
            return
        }
        guard !name.isEmpty else { return }
        let needle = name.lowercased()
        for app in NSWorkspace.shared.runningApplications {
            let label = (app.localizedName ?? "").lowercased()
            let bundle = (app.bundleIdentifier ?? "").lowercased()
            if label.contains(needle) || bundle.contains(needle) {
                app.terminate()
            }
        }
    }

    static func perform(_ action: KeenAction) {
        switch action {
        case .none:
            break
        case .runShortcut(let name):
            runShortcut(named: name)
        case .openURL(let url):
            openURL(url)
        case .shell:
            // Legacy schedules may still decode this case. It is deliberately
            // inert: arbitrary commands are not a product feature.
            break
        case .quitApp(let name):
            quitApp(named: name)
        }
    }
}
