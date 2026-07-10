import Foundation

@MainActor
enum SchedTimeFormat {
    static func string(from date: Date, includeSeconds: Bool = false) -> String {
        let preferences = ScheduleStore.shared.store
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = pattern(
            style: preferences.hourStyle,
            showAMPM: preferences.showAMPM,
            includeSeconds: includeSeconds
        )
        return formatter.string(from: date)
    }

    static func timeAndPeriod(from date: Date) -> (time: String, period: String) {
        let preferences = ScheduleStore.shared.store
        let uses24 = resolvedUses24Hour(preferences.hourStyle)
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = uses24 ? "HH:mm" : "h:mm"
        let period: String
        if uses24 || !preferences.showAMPM {
            period = ""
        } else {
            let periodFormatter = DateFormatter()
            periodFormatter.locale = .autoupdatingCurrent
            periodFormatter.dateFormat = "a"
            period = periodFormatter.string(from: date).lowercased()
        }
        return (formatter.string(from: date), period)
    }

    static func dateContext(from date: Date) -> String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter.string(from: date)
    }

    static func resolvedUses24Hour(_ style: HourStyle) -> Bool {
        switch style {
        case .twentyFourHour: return true
        case .twelveHour: return false
        case .system:
            guard let pattern = DateFormatter.dateFormat(
                fromTemplate: "j",
                options: 0,
                locale: .autoupdatingCurrent
            ) else { return false }
            return pattern.contains("H") || pattern.contains("k")
        }
    }

    private static func pattern(style: HourStyle, showAMPM: Bool, includeSeconds: Bool) -> String {
        let seconds = includeSeconds ? ":ss" : ""
        if resolvedUses24Hour(style) { return "HH:mm\(seconds)" }
        return "h:mm\(seconds)\(showAMPM ? " a" : "")"
    }
}
