import Foundation

@MainActor
enum URLHandler {
    static func handle(_ url: URL) {
        guard let scheme = url.scheme?.lowercased(), ["sched", "keen"].contains(scheme) else { return }
        let host = (url.host ?? "").lowercased()
        let params = queryParams(url)

        switch host {
        case "open":
            switch (params["section"] ?? "plan").lowercased() {
            case "calendar": MainWindowController.shared.showCalendar(date: .now)
            case "timer":
                MainWindowController.shared.showSection(.timer)
                MainWindowController.shared.showWindow()
            case "limits":
                MainWindowController.shared.showSection(.limits)
                MainWindowController.shared.showWindow()
            case "ai":
                MainWindowController.shared.showSection(.ai)
                MainWindowController.shared.showWindow()
            case "preferences", "settings":
                MainWindowController.shared.showSection(.settings)
                MainWindowController.shared.showWindow()
            default:
                MainWindowController.shared.showSection(.schedule)
                MainWindowController.shared.showWindow()
            }

        case "reminder":
            let pathID = url.pathComponents.dropFirst().first
            if let raw = params["id"] ?? pathID, let id = UUID(uuidString: raw) {
                MainWindowController.shared.showAlarm(id)
            } else {
                MainWindowController.shared.showSection(.schedule)
                MainWindowController.shared.showWindow()
            }

        case "calendar":
            let date = params["date"].flatMap(parseISODate) ?? .now
            MainWindowController.shared.showCalendar(date: date)

        case "timer", "in":
            let title = params["title"] ?? params["name"] ?? "Focus"
            let minutes = Int(params["minutes"] ?? params["m"] ?? "25") ?? 25
            let level = InterventionLevel(rawValue: params["level"] ?? "") ?? ScheduleStore.shared.store.defaultLevel
            let action = actionFrom(params)
            _ = Scheduler.shared.scheduleIn(title: title, note: params["note"] ?? "", minutes: minutes, level: level, action: action)

        case "at":
            let title = params["title"] ?? params["name"] ?? "Alarm"
            let level = InterventionLevel(rawValue: params["level"] ?? "") ?? ScheduleStore.shared.store.defaultLevel
            let action = actionFrom(params)
            if let minutes = Int(params["minutes"] ?? ""), minutes > 0 {
                _ = Scheduler.shared.scheduleIn(title: title, minutes: minutes, level: level, action: action)
            } else if let time = params["time"], let date = parseTimeToday(time) {
                _ = Scheduler.shared.scheduleAt(title: title, date: date, level: level, repeatDaily: params["daily"] == "1", action: action)
            }

        case "snooze":
            let minutes = Int(params["minutes"] ?? params["m"] ?? "") ?? ScheduleStore.shared.store.snoozeMinutes
            ScheduleStore.shared.setSnoozeMinutes(minutes)

        case "dismiss":
            NotificationCenter.default.post(name: .schedDismissAll, object: nil)

        case "shortcut", "run":
            if let name = params["name"] ?? params["shortcut"] {
                ShortcutsBridge.runShortcut(named: name)
            }

        case "idle":
            if let m = Int(params["minutes"] ?? "") {
                ScheduleStore.shared.setIdleNudge(minutes: m > 0 ? m : nil)
            }

        default:
            if host.isEmpty, let minutes = Int(params["minutes"] ?? "25") {
                _ = Scheduler.shared.scheduleIn(title: "Timer", minutes: minutes)
            }
        }
    }

    private static func actionFrom(_ params: [String: String]) -> SchedAction {
        if let shortcut = params["shortcut"] { return .runShortcut(name: shortcut) }
        if let url = params["url"] { return .openURL(url: url) }
        return .none
    }

    private static func queryParams(_ url: URL) -> [String: String] {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return [:] }
        var out: [String: String] = [:]
        for item in items {
            if let v = item.value {
                out[item.name.lowercased()] = v
            }
        }
        return out
    }

    private static func parseISODate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func parseTimeToday(_ time: String) -> Date? {
        let formats = ["HH:mm", "H:mm", "h:mm a", "h:mma"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in formats {
            formatter.dateFormat = format
            if let parsed = formatter.date(from: time.trimmingCharacters(in: .whitespaces)) {
                let cal = Calendar.current
                let comps = cal.dateComponents([.hour, .minute], from: parsed)
                return cal.date(bySettingHour: comps.hour ?? 0, minute: comps.minute ?? 0, second: 0, of: .now)
            }
        }
        return nil
    }

}

extension Notification.Name {
    static let schedDismissAll = Notification.Name("sched.dismissAll")
}
