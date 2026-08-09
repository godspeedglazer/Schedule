import Foundation

enum SchedTextLimits {
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

enum AlarmSound: Codable, Equatable, Hashable {
    case none
    case system(name: String)
    case imported(fileName: String)
    case externalFile(path: String)

    static let defaultSystem: AlarmSound = .system(name: "Glass")

    var displayName: String {
        switch self {
        case .none:
            return "None"
        case .system(let name):
            return name
        case .imported(let fileName):
            return URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        case .externalFile(let path):
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        }
    }

    var detail: String {
        switch self {
        case .none:
            return "Silent"
        case .system:
            return "macOS sound"
        case .imported:
            return "Managed by Sched"
        case .externalFile:
            return "Linked file"
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

enum SchedActionKind: String, Codable, CaseIterable {
    case none
    case shortcut
    case url
    case shell
    case quitApp

    /// Actions intentionally exposed in the product UI. `shell` remains only
    /// for decoding older schedule files and is never executed.
    static let userFacingCases: [SchedActionKind] = [.none, .shortcut, .url, .quitApp]

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

enum SchedAction: Codable, Equatable {
    case none
    case runShortcut(name: String)
    case openURL(url: String)
    case shell(command: String)
    case quitApp(name: String)

    var kind: SchedActionKind {
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

    static func from(kind: SchedActionKind, payload: String) -> SchedAction {
        switch kind {
        case .none: .none
        case .shortcut: .runShortcut(name: payload)
        case .url: .openURL(url: payload)
        case .shell: .shell(command: payload)
        case .quitApp: .quitApp(name: payload)
        }
    }
}

struct SchedAppWatch: Codable, Identifiable, Equatable {
    var id: UUID
    var appName: String
    var bundleId: String?
    var executablePath: String?
    var maxMinutes: Int
    var level: InterventionLevel
    var action: SchedAction
    var enabled: Bool

    init(
        id: UUID = UUID(),
        appName: String,
        bundleId: String? = nil,
        executablePath: String? = nil,
        maxMinutes: Int = 45,
        level: InterventionLevel = .gentle,
        action: SchedAction = .none,
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
        action = try c.decode(SchedAction.self, forKey: .action)
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

    func interventionAlarm(frontName: String) -> SchedAlarm {
        SchedAlarm(
            title: "\(frontName) — time's up",
            note: "You've had this app open for \(maxMinutes)+ minutes.",
            fireAt: .now,
            level: level,
            action: action
        )
    }
}

struct SchedAlarm: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var note: String
    var fireAt: Date
    var level: InterventionLevel
    var action: SchedAction
    var sound: AlarmSound?
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
        action: SchedAction = .none,
        sound: AlarmSound? = nil,
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
        self.sound = sound
        self.repeatDaily = repeatDaily
        self.enabled = enabled
        self.isTimer = isTimer
        self.pausedRemainingSeconds = pausedRemainingSeconds
    }

    enum CodingKeys: String, CodingKey {
        case id, title, note, fireAt, level, action, sound, repeatDaily, enabled
        case isTimer, pausedRemainingSeconds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        fireAt = try c.decode(Date.self, forKey: .fireAt)
        level = try c.decode(InterventionLevel.self, forKey: .level)
        action = try c.decodeIfPresent(SchedAction.self, forKey: .action) ?? .none
        sound = try c.decodeIfPresent(AlarmSound.self, forKey: .sound)
        repeatDaily = try c.decodeIfPresent(Bool.self, forKey: .repeatDaily) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        isTimer = try c.decodeIfPresent(Bool.self, forKey: .isTimer) ?? false
        pausedRemainingSeconds = try c.decodeIfPresent(Int.self, forKey: .pausedRemainingSeconds)
    }
}

struct SchedStore: Codable {
    var alarms: [SchedAlarm]
    var appWatches: [SchedAppWatch]
    var defaultLevel: InterventionLevel
    var snoozeMinutes: Int
    var idleMinutesBeforeNudge: Int?
    var launchAtLogin: Bool
    var playSoundOnAlert: Bool
    var repeatSoundOnAlert: Bool
    var defaultSound: AlarmSound
    var soundVolume: Double
    var systemNotificationsEnabled: Bool
    var headlessWhenClosed: Bool
    var menuBarShowIcon: Bool
    var menuBarShowDate: Bool
    var menuBarShowTime: Bool
    var menuBarShowSeconds: Bool
    var menuBarClockEnabled: Bool
    var menuBarTimerEnabled: Bool
    var menuBarTimerHideWhenIdle: Bool
    var floatingTimerAutoShow: Bool
    var floatingTimerAlwaysOnTop: Bool
    var hourStyle: HourStyle
    var showAMPM: Bool

    static let empty = SchedStore(
        alarms: [],
        appWatches: [],
        defaultLevel: .gentle,
        snoozeMinutes: 5,
        idleMinutesBeforeNudge: nil,
        launchAtLogin: false,
        playSoundOnAlert: true,
        repeatSoundOnAlert: false,
        defaultSound: .defaultSystem,
        soundVolume: 0.8,
        systemNotificationsEnabled: true,
        headlessWhenClosed: true,
        menuBarShowIcon: true,
        menuBarShowDate: false,
        menuBarShowTime: true,
        menuBarShowSeconds: false,
        menuBarClockEnabled: true,
        menuBarTimerEnabled: true,
        menuBarTimerHideWhenIdle: false,
        floatingTimerAutoShow: false,
        floatingTimerAlwaysOnTop: true,
        hourStyle: .system,
        showAMPM: true
    )

    enum CodingKeys: String, CodingKey {
        case alarms, appWatches, defaultLevel, snoozeMinutes, idleMinutesBeforeNudge
        case launchAtLogin, playSoundOnAlert, repeatSoundOnAlert, defaultSound, soundVolume
        case systemNotificationsEnabled, headlessWhenClosed
        case menuBarShowIcon, menuBarShowDate, menuBarShowTime, menuBarShowSeconds
        case menuBarClockEnabled, menuBarTimerEnabled, menuBarTimerHideWhenIdle
        case floatingTimerAutoShow, floatingTimerAlwaysOnTop
        case hourStyle, showAMPM
    }

    init(
        alarms: [SchedAlarm],
        appWatches: [SchedAppWatch],
        defaultLevel: InterventionLevel,
        snoozeMinutes: Int,
        idleMinutesBeforeNudge: Int?,
        launchAtLogin: Bool,
        playSoundOnAlert: Bool,
        repeatSoundOnAlert: Bool,
        defaultSound: AlarmSound,
        soundVolume: Double,
        systemNotificationsEnabled: Bool,
        headlessWhenClosed: Bool,
        menuBarShowIcon: Bool,
        menuBarShowDate: Bool,
        menuBarShowTime: Bool,
        menuBarShowSeconds: Bool,
        menuBarClockEnabled: Bool,
        menuBarTimerEnabled: Bool,
        menuBarTimerHideWhenIdle: Bool,
        floatingTimerAutoShow: Bool,
        floatingTimerAlwaysOnTop: Bool,
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
        self.defaultSound = defaultSound
        self.soundVolume = soundVolume
        self.systemNotificationsEnabled = systemNotificationsEnabled
        self.headlessWhenClosed = headlessWhenClosed
        self.menuBarShowIcon = menuBarShowIcon
        self.menuBarShowDate = menuBarShowDate
        self.menuBarShowTime = menuBarShowTime
        self.menuBarShowSeconds = menuBarShowSeconds
        self.menuBarClockEnabled = menuBarClockEnabled
        self.menuBarTimerEnabled = menuBarTimerEnabled
        self.menuBarTimerHideWhenIdle = menuBarTimerHideWhenIdle
        self.floatingTimerAutoShow = floatingTimerAutoShow
        self.floatingTimerAlwaysOnTop = floatingTimerAlwaysOnTop
        self.hourStyle = hourStyle
        self.showAMPM = showAMPM
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alarms = try c.decode([SchedAlarm].self, forKey: .alarms)
        appWatches = try c.decodeIfPresent([SchedAppWatch].self, forKey: .appWatches) ?? []
        defaultLevel = try c.decode(InterventionLevel.self, forKey: .defaultLevel)
        snoozeMinutes = try c.decode(Int.self, forKey: .snoozeMinutes)
        idleMinutesBeforeNudge = try c.decodeIfPresent(Int.self, forKey: .idleMinutesBeforeNudge)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        playSoundOnAlert = try c.decodeIfPresent(Bool.self, forKey: .playSoundOnAlert) ?? true
        repeatSoundOnAlert = try c.decodeIfPresent(Bool.self, forKey: .repeatSoundOnAlert) ?? false
        defaultSound = try c.decodeIfPresent(AlarmSound.self, forKey: .defaultSound) ?? .defaultSystem
        soundVolume = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? 0.8))
        systemNotificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .systemNotificationsEnabled) ?? true
        headlessWhenClosed = try c.decodeIfPresent(Bool.self, forKey: .headlessWhenClosed) ?? true
        menuBarShowIcon = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowIcon) ?? true
        menuBarShowDate = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowDate) ?? false
        menuBarShowTime = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowTime) ?? true
        menuBarShowSeconds = try c.decodeIfPresent(Bool.self, forKey: .menuBarShowSeconds) ?? false
        menuBarClockEnabled = try c.decodeIfPresent(Bool.self, forKey: .menuBarClockEnabled) ?? true
        menuBarTimerEnabled = try c.decodeIfPresent(Bool.self, forKey: .menuBarTimerEnabled) ?? true
        menuBarTimerHideWhenIdle = try c.decodeIfPresent(Bool.self, forKey: .menuBarTimerHideWhenIdle) ?? false
        floatingTimerAutoShow = try c.decodeIfPresent(Bool.self, forKey: .floatingTimerAutoShow) ?? false
        floatingTimerAlwaysOnTop = try c.decodeIfPresent(Bool.self, forKey: .floatingTimerAlwaysOnTop) ?? true
        hourStyle = try c.decodeIfPresent(HourStyle.self, forKey: .hourStyle) ?? .system
        showAMPM = try c.decodeIfPresent(Bool.self, forKey: .showAMPM) ?? true
    }
}
