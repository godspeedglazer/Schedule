import AppKit

struct RunningApp: Equatable, Identifiable {
    var id: String { bundleId ?? executablePath ?? name }
    let name: String
    let bundleId: String?
    let executablePath: String?
    let icon: NSImage?

    var menuTitle: String { name }
}

@MainActor
enum RunningApps {
    static func availableTargets() -> [RunningApp] {
        var targets = list()
        var seen = Set(targets.map(\.id))
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications/Utilities", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
        ]
        for root in roots {
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in urls where url.pathExtension.lowercased() == "app" {
                let bundle = Bundle(url: url)
                let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let target = RunningApp(
                    name: name,
                    bundleId: bundle?.bundleIdentifier,
                    executablePath: bundle?.executableURL?.standardizedFileURL.path,
                    icon: nil
                )
                guard seen.insert(target.id).inserted else { continue }
                targets.append(target)
            }
        }
        return targets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func list() -> [RunningApp] {
        let selfBundle = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular
                    && app.bundleIdentifier != selfBundle
            }
            .compactMap { app -> RunningApp? in
                let bundleId = app.bundleIdentifier
                let path = app.executableURL?.path
                let identity = bundleId ?? path
                guard let identity, !identity.isEmpty, seen.insert(identity).inserted else { return nil }
                let name = app.localizedName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? app.executableURL?.deletingPathExtension().lastPathComponent
                    ?? identity
                return RunningApp(name: name, bundleId: bundleId, executablePath: path, icon: nil)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func populate(_ popup: NSPopUpButton, selectedBundleId: String?, selectedName: String?) {
        popup.removeAllItems()
        let apps = availableTargets()
        if apps.isEmpty {
            popup.addItem(withTitle: "No applications found")
            popup.isEnabled = false
            return
        }
        popup.isEnabled = true
        for app in apps {
            popup.addItem(withTitle: app.menuTitle)
            if let item = popup.item(withTitle: app.menuTitle) {
                item.representedObject = [
                    "name": app.name,
                    "bundleId": app.bundleId ?? "",
                    "executablePath": app.executablePath ?? "",
                ]
            }
            if let icon = app.icon, let item = popup.item(withTitle: app.menuTitle) {
                item.image = icon
                item.image?.size = NSSize(width: 16, height: 16)
            }
        }
        if let bundleId = selectedBundleId,
           let idx = apps.firstIndex(where: { $0.bundleId == bundleId }) {
            popup.selectItem(at: idx)
        } else if let name = selectedName,
                  let idx = apps.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            popup.selectItem(at: idx)
        } else {
            popup.selectItem(at: 0)
        }
    }

    static func selectedApp(from popup: NSPopUpButton) -> RunningApp? {
        guard popup.isEnabled,
              let values = popup.selectedItem?.representedObject as? [String: String],
              let name = values["name"] else { return nil }
        let bundleId = values["bundleId"].flatMap { $0.isEmpty ? nil : $0 }
        let path = values["executablePath"].flatMap { $0.isEmpty ? nil : $0 }
        return RunningApp(name: name, bundleId: bundleId, executablePath: path, icon: popup.selectedItem?.image)
    }

    static func target(for url: URL) -> RunningApp? {
        let normalized = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDirectory) else { return nil }

        if isDirectory.boolValue, normalized.pathExtension.lowercased() == "app" {
            let bundle = Bundle(url: normalized)
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? normalized.deletingPathExtension().lastPathComponent
            return RunningApp(
                name: name,
                bundleId: bundle?.bundleIdentifier,
                executablePath: bundle?.executableURL?.standardizedFileURL.path,
                icon: NSWorkspace.shared.icon(forFile: normalized.path)
            )
        }

        guard !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: normalized.path) else { return nil }
        return RunningApp(
            name: normalized.deletingPathExtension().lastPathComponent,
            bundleId: nil,
            executablePath: normalized.path,
            icon: NSWorkspace.shared.icon(forFile: normalized.path)
        )
    }

    static func quit(bundleId: String) {
        guard !bundleId.isEmpty else { return }
        for app in NSWorkspace.shared.runningApplications where app.bundleIdentifier == bundleId {
            app.terminate()
        }
    }

    static func quit(named name: String, bundleId: String?, executablePath: String? = nil) {
        if let bundleId, !bundleId.isEmpty {
            quit(bundleId: bundleId)
            return
        }
        guard !name.isEmpty else { return }
        let needle = name.lowercased()
        for app in NSWorkspace.shared.runningApplications {
            let label = (app.localizedName ?? "").lowercased()
            let bundle = (app.bundleIdentifier ?? "").lowercased()
            let path = app.executableURL?.standardizedFileURL.path
            let pathMatches = executablePath.map { URL(fileURLWithPath: $0).standardizedFileURL.path == path } ?? false
            if pathMatches || label.contains(needle) || bundle.contains(needle) {
                app.terminate()
            }
        }
    }
}

@MainActor
func keenAppPopup() -> NSPopUpButton {
    let popup = NSPopUpButton()
    popup.translatesAutoresizingMaskIntoConstraints = false
    popup.heightAnchor.constraint(equalToConstant: 32).isActive = true
    return popup
}
