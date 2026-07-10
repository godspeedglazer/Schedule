import Foundation

enum KeenTextLimits {
    static let title = 120
    static let note = 500
    static let action = 300

    static func clean(_ value: String, limit: Int) -> String {
        String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(limit))
    }
}

enum HourStyle: String, Codable, CaseIterable {
    case system
    case twelveHour
    case twentyFourHour

    var label: String {
        switch self {
        case .system: "System"
        case .twelveHour: "12-hour"
        case .twentyFourHour: "24-hour"
        }
    }
}

enum InterventionLevel: String, Codable, CaseIterable, Identifiable {
    case gentle
    case focus
    case takeover

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gentle: "Corner card"
        case .focus: "Center card"
        case .takeover: "Full screen"
        }
    }

    var detail: String {
        switch self {
        case .gentle: "Movable and remembered"
        case .focus: "Centered with a soft dim"
        case .takeover: "Full-screen pause"
        }
    }
}

enum KeenActionKind: String, Codable, CaseIterable {
    case none
    case shortcut
    case url
    case shell
    case quitApp

    /// Actions intentionally exposed in the product UI. `shell` remains only
    /// for decoding older schedule files and is never executed.
    static let userFacingCases: [KeenActionKind] = [.none, .shortcut, .url, .quitApp]

    var displayName: String {
        switch self {
        case .none: "Nothing"
        case .shortcut: "Run Shortcut"
        case .url: "Open link"
        case .quitApp: "Quit app"
        case .shell: "Unsupported legacy action"
        }
    }
}

enum KeenAction: Codable, Equatable {
    case none
    case runShortcut(name: String)
    case openURL(url: String)
    case shell(command: String)
    case quitApp(name: String)

    var kind: KeenActionKind {
        switch self {
        case .none: .none
        case .runShortcut: .shortcut
        case .openURL: .url
        case .shell: .shell
        case .quitApp: .quitApp
        }
    }

    var payload: String {
        switch self {
        case .none: ""
        case .runShortcut(let name): name
        case .openURL(let url): url
        case .shell(let command): command
        case .quitApp(let name): name
        }
    }

    static func from(kind: KeenActionKind, payload: String) -> KeenAction {
        switch kind {
        case .none: .none
        case .shortcut: .runShortcut(name: payload)
        case .url: .openURL(url: payload)
        case .shell: .shell(command: payload)
        case .quitApp: .quitApp(name: payload)
        }
    }
}

struct KeenAppWatch: Codable, Identifiable, Equatable {
    var id: UUID
    var appName: String
    var bundleId: String?
    var executablePath: String?
    var maxMinutes: Int
    var level: InterventionLevel
    var action: KeenAction
    var enabled: Bool

    init(
        id: UUID = UUID(),
        appName: String,
        bundleId: String? = nil,
        executablePath: String? = nil,
        maxMinutes: Int = 45,
        level: InterventionLevel = .gentle,
        action: KeenAction = .none,
        enabled: Bool = true
    ) {
        self.id = id
        self.appName = appName
        self.bundleId = bundleId
        self.executablePath = executablePath
        self.maxMinutes = maxMinutes
        self.level = level
        self.action = action
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey {
        case id, appName, bundleId, executablePath, maxMinutes, level, action, enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        appName = try c.decode(String.self, forKey: .appName)
        bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
        executablePath = try c.decodeIfPresent(String.self, forKey: .executablePath)
        maxMinutes = try c.decode(Int.self, forKey: .maxMinutes)
        level = try c.decode(InterventionLevel.self, forKey: .level)
        action = try c.decode(KeenAction.self, forKey: .action)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    func matches(appName frontName: String, bundleId frontBundle: String?, executablePath frontPath: String?) -> Bool {
        if let bundleId, !bundleId.isEmpty, bundleId == frontBundle { return true }
        if let executablePath, !executablePath.isEmpty, let frontPath {
            if URL(fileURLWithPath: executablePath).standardizedFileURL.path
                == URL(fileURLWithPath: frontPath).standardizedFileURL.path {
                return true
            }
        }
        let needle = appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return false }
        return frontName.lowercased().contains(needle)
            || (frontBundle?.lowercased().contains(needle) ?? false)
            || (frontPath?.lowercased().contains(needle) ?? false)
    }

    func interventionAlarm(frontName: String) -> KeenAlarm {
        KeenAlarm(
            title: "\(frontName) — time's up",
            note: "You've had this app open for \(maxMinutes)+ minutes.",
            fireAt: .now,
            level: level,
            action: action
        )
    }
}

struct KeenAlarm: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var note: String
    var fireAt: Date
    var level: InterventionLevel
    var action: KeenAction
    var repeatDaily: Bool
    var enabled: Bool
    var isTimer: Bool
    var pausedRemainingSeconds: Int?

    init(
        id: UUID = UUID(),
        title: String,
        note: String = "",
        fireAt: Date,
        level: InterventionLevel = .focus,
        action: KeenAction = .none,
        repeatDaily: Bool = false,
        enabled: Bool = true,
        isTimer: Bool = false,
        pausedRemainingSeconds: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.fireAt = fireAt
        self.level = level
        self.action = action
        self.repeatDaily = repeatDaily
        self.enabled = enabled
        self.isTimer = isTimer
        self.pausedRemainingSeconds = pausedRemainingSeconds
    }

    enum CodingKeys: String, CodingKey {
        case id, title, note, fireAt, level, action, repeatDaily, enabled
        case isTimer, pausedRemainingSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        fireAt = try c.decode(Date.self, forKey: .fireAt)
        level = try c.decode(InterventionLevel.self, forKey: .level)
        action = try c.decodeIfPresent(KeenAction.self, forKey: .action) ?? .none
        repeatDaily = try c.decodeIfPresent(Bool.self, forKey: .repeatDaily) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        isTimer = try c.decodeIfPresent(Bool.self, forKey: .isTimer) ?? false
        pausedRemainingSeconds = try c.decodeIfPresent(Int.self, forKey: .pausedRemainingSeconds)
    }
}

struct KeenStore: Codable {
    var alarms: [KeenAlarm]
    var appWatches: [KeenAppWatch]
    var defaultLevel: InterventionLevel
    var snoozeMinutes: Int
    var idleMinutesBeforeNudge: Int?
    var launchAtLogin: Bool
    var playSoundOnAlert: Bool
    var repeatSoundOnAlert: Bool
    var systemNotificationsEnabled: Bool
    var headlessWhenClosed: Bool
    var menuBarShowIcon: Bool
    var menuBarShowDate: Bool
    var menuBarShowTime: Bool
    var menuBarShowSeconds: Bool
    var menuBarShowNextCountdown: Bool
    var hourStyle: HourStyle
    var showAMPM: Bool

    static let empty = KeenStore(
        alarms: [],
        appWatches: [],
        defaultLevel: .gentle,
        snoozeMinutes: 5,
        idleMinutesBeforeNudge: nil,
        launchAtLogin: false,
        playSoundOnAlert: true,
        repeatSoundOnAlert: false,
        systemNotificationsEnabled: true,
        headlessWhenClosed: true,
        menuBarShowIcon: true,
        menuBarShowDate: false,
        menuBarShowTime: true,
        menuBarShowSeconds: false,
        menuBarShowNextCountdown: false,
        hourStyle: .system,
        showAMPM: true
    )

    enum CodingKeys: String, CodingKey {
        case alarms, appWatches, defaultLevel, snoozeMinutes, idleMinutesBeforeNudge
        case launchAtLogin, playSoundOnAlert, repeatSoundOnAlert, systemNotificationsEnabled, headlessWhenClosed
        case menuBarShowIcon, menuBarShowDate, menuBarShowTime, menuBarShowSeconds, menuBarShowNextCountdown
        case hourStyle, showAMPM
    }

    init(
        alarms: [KeenAlarm],
        appWatches: [KeenAppWatch],
        defaultLevel: InterventionLevel,
        snoozeMinutes: Int,
        idleMinutesBeforeNudge: Int?,
        launchAtLogin: Bool,
        playSoundOnAlert: Bool,
        repeatSoundOnAlert: Bool,
        systemNotificationsEnabled: Bool,
        headlessWhenClosed: Bool,
        menuBarShowIcon: Bool,
        menuBarShowDate: Bool,
        menuBarShowTime: Bool,
        menuBarShowSeconds: Bool,
        menuBarShowNextCountdown: Bool,
        hourStyle: HourStyle,
        showAMPM: Bool
    ) {
        self.alarms = alarms
        self.appWatches = appWatches
        self.defaultLevel = defaultLevel
        self.snoozeMinutes = snoozeMinutes
        self.idleMinutesBeforeNudge = idleMinutesBeforeNudge
        self.launchAtLogin = launchAtLogin
        self.playSoundOnAlert = playSoundOnAlert
        self.repeatSoundOnAlert = repeatSoundOnAlert
        self.systemNotificationsEnabled = systemNotificationsEnabled
        self.headlessWhenClosed = headlessWhenClosed
        self.menuBarShowIcon = menuBarShowIcon
        self.menuBarShowDate = menuBarShowDate
        self.menuBarShowTime = menuBarShowTime
        self.menuBarShowSeconds = menuBarShowSeconds
        self.menuBarShowNextCountdown = menuBarShowNextCountdown
        self.hourStyle = hourStyle
        self.showAMPM = showAMPM
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alarms = try c.decode([KeenAlarm].self, forKey: .alarms)
        appWatches = try c.decodeIfPresent([KeenAppWatch].self, forKey: .appWatches) ?? []
        defaultLevel = try c.decode(InterventionLevel.self, forKey: .defaultLevel)
        snoozeMinutes = try c.decode(Int.self, forKey: .snoozeMinutes)
        idleMinutesBeforeNudge = try c.decodeIfPresent(Int.self, forKey: .idleMinutesBeforeNudge)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        playSoundOnAlert = try c.decodeIfPresent(Bool.self, forKey: .playSoundOnAlert) ?? true
        repeatSoundOnAlert = try c.decodeIfPresent(Bool.self, forKey: .repeatSoundOnAlert) ?? false
        systemNotificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .systemNotificationsEnabled) ?? true
        headlessWhenClosed = try c.decodeIfPresent(Bool.self, forKey: .headlessWhenClosed) ?? true
        menuBarShowIcon = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowIcon) ?? true
        menuBarShowDate = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowDate) ?? false
        menuBarShowTime = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowTime) ?? true
        menuBarShowSeconds = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowSeconds) ?? false
        menuBarShowNextCountdown = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowNextCountdown) ?? false
        hourStyle = try c.decodeIfPresent(HourStyle.self, forKey: .hourStyle) ?? .system
        showAMPM = try c.decodeIfPresent(Bool.self, forKey: .showAMPM) ?? true
    }
}
