import Foundation
import XCTest
@testable import Sched

final class ModelMigrationTests: XCTestCase {
    func testLegacyStoreGetsCompactMenuBarDefaults() throws {
        let json = """
        {
          "alarms": [],
          "appWatches": [],
          "defaultLevel": "gentle",
          "snoozeMinutes": 5,
          "idleMinutesBeforeNudge": null,
          "launchAtLogin": false,
          "playSoundOnAlert": true,
          "systemNotificationsEnabled": true,
          "headlessWhenClosed": true
        }
        """.data(using: .utf8)!

        let store = try JSONDecoder().decode(SchedStore.self, from: json)
        XCTAssertTrue(store.menuBarShowIcon)
        XCTAssertFalse(store.menuBarShowDate)
        XCTAssertTrue(store.menuBarShowTime)
        XCTAssertFalse(store.menuBarShowSeconds)
        XCTAssertFalse(store.repeatSoundOnAlert)
        XCTAssertEqual(store.defaultSound, .defaultSystem)
        XCTAssertEqual(store.soundVolume, 0.8, accuracy: 0.001)
        XCTAssertEqual(store.dockPresence, .whileWindowOpen)
        XCTAssertTrue(store.menuBarClockEnabled)
        XCTAssertTrue(store.menuBarTimerEnabled)
        XCTAssertFalse(store.menuBarTimerHideWhenIdle)
        XCTAssertFalse(store.floatingTimerAutoShow)
        XCTAssertTrue(store.floatingTimerAlwaysOnTop)
        XCTAssertEqual(store.hourStyle, .system)
        XCTAssertTrue(store.showAMPM)
        XCTAssertEqual(store.aiSettings, .default)
    }

    func testLegacyAlarmGetsNonTimerDefaults() throws {
        let legacy = LegacyAlarm(
            id: UUID(),
            title: "Review",
            note: "Close loops",
            fireAt: Date(timeIntervalSince1970: 1_800_000_000),
            level: .focus,
            action: .none,
            repeatDaily: false,
            enabled: true
        )
        let data = try JSONEncoder().encode(legacy)
        let alarm = try JSONDecoder().decode(SchedAlarm.self, from: data)
        XCTAssertFalse(alarm.isTimer)
        XCTAssertNil(alarm.pausedRemainingSeconds)
        XCTAssertNil(alarm.calendarEventIdentifier)
    }

    func testAlarmSoundChoicesRoundTrip() throws {
        let choices: [AlarmSound] = [
            .none,
            .system(name: "Glass"),
            .imported(fileName: "soft-chime.mp3"),
            .externalFile(path: "/Users/example/Music/alarm.mp3"),
        ]
        for choice in choices {
            let data = try JSONEncoder().encode(choice)
            XCTAssertEqual(try JSONDecoder().decode(AlarmSound.self, from: data), choice)
        }
    }

    func testAlarmCanOverrideDefaultSound() throws {
        let original = SchedAlarm(
            title: "Sound check",
            fireAt: Date(timeIntervalSince1970: 1_800_000_000),
            sound: .system(name: "Ping")
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SchedAlarm.self, from: data)
        XCTAssertEqual(decoded.sound, .system(name: "Ping"))
    }

    func testCalendarLinkRoundTrips() throws {
        let original = SchedAlarm(
            title: "Meeting",
            fireAt: Date(timeIntervalSince1970: 1_800_000_000),
            calendarEventIdentifier: "event-123"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SchedAlarm.self, from: data)
        XCTAssertEqual(decoded.calendarEventIdentifier, "event-123")
    }

    func testPausedTimerRoundTrips() throws {
        let original = SchedAlarm(
            title: "Focus",
            fireAt: .now,
            level: .gentle,
            enabled: false,
            isTimer: true,
            pausedRemainingSeconds: 317
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SchedAlarm.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testNewAppWatchHasNoDestructiveFollowUpByDefault() {
        let watch = SchedAppWatch(appName: "Example")
        XCTAssertEqual(watch.action, .none)
    }

    func testAppWatchUsesExactBundleOrExecutableIdentity() {
        let watch = SchedAppWatch(
            appName: "Example",
            bundleId: "com.example.Editor",
            executablePath: "/Applications/Example.app/Contents/MacOS/Example"
        )
        XCTAssertTrue(watch.matches(appName: "Renamed", bundleId: "com.example.Editor", executablePath: nil))
        XCTAssertTrue(watch.matches(appName: "Renamed", bundleId: nil, executablePath: "/Applications/Example.app/Contents/MacOS/Example"))
        XCTAssertFalse(watch.matches(appName: "Unrelated", bundleId: "com.other.App", executablePath: "/tmp/other"))
    }

    func testTextLimitsTrimAndBoundUntrustedInput() {
        let oversized = "   " + String(repeating: "x", count: 300) + "   "
        XCTAssertEqual(SchedTextLimits.clean(oversized, limit: SchedTextLimits.title).count, SchedTextLimits.title)
        XCTAssertFalse(SchedTextLimits.clean("  Useful title  ", limit: SchedTextLimits.title).hasPrefix(" "))
    }

    func testAIProviderDetectionUnderstandsKeysAndLocalEndpoints() {
        XCTAssertEqual(AIProviderDetector.provider(forKeyPrefix: "sk-ant-example"), .anthropic)
        XCTAssertEqual(AIProviderDetector.provider(forKeyPrefix: "gsk_example"), .groq)
        XCTAssertEqual(AIProviderDetector.provider(forEndpoint: "http://localhost:11434"), .ollama)
        XCTAssertEqual(AIProviderDetector.provider(forEndpoint: "http://127.0.0.1:1234/v1"), .lmStudio)
        XCTAssertEqual(
            AIProviderDetector.detect(environment: ["GEMINI_API_KEY": "secret"])?.provider,
            .gemini
        )
    }

    func testAIPacketIsPortableAndDoesNotContainSecrets() throws {
        var store = SchedStore.empty
        store.aiSettings = SchedAISettings(provider: .openAI, endpoint: "https://api.openai.com", model: "test", stopOwnedServerOnQuit: true)
        store.alarms = [SchedAlarm(title: "Review", note: "Launch notes", fireAt: Date(timeIntervalSince1970: 1_800_000_000))]
        let files = try AIPacketBuilder.files(store: store, request: "Organize tomorrow", now: Date(timeIntervalSince1970: 1_800_000_100))
        XCTAssertEqual(Set(files.keys), Set(["README.md", "request.md", "sched-context.json"]))
        let joined = files.values.compactMap { String(data: $0, encoding: .utf8) }.joined()
        XCTAssertTrue(joined.contains("Review"))
        XCTAssertTrue(joined.contains("Organize tomorrow"))
        XCTAssertFalse(joined.lowercased().contains("api_key"))
        XCTAssertFalse(joined.contains("secret"))
    }

    func testAIPacketCanLimitContextToTimersAndAppLimits() throws {
        var store = SchedStore.empty
        store.alarms = [
            SchedAlarm(title: "Reminder", fireAt: .now),
            SchedAlarm(title: "Focus", fireAt: .now, isTimer: true, pausedRemainingSeconds: 300),
        ]
        store.appWatches = [SchedAppWatch(appName: "Editor", maxMinutes: 45)]
        let files = try AIPacketBuilder.files(
            store: store,
            request: "Review focus",
            options: .init(includeReminders: false, includeTimers: true, includeAppLimits: true, includeWorkspace: false)
        )
        let context = try XCTUnwrap(files["sched-context.json"])
        let decoded = try JSONDecoder.schedPacket.decode(SchedAIPacketContext.self, from: context)
        XCTAssertTrue(decoded.reminders.isEmpty)
        XCTAssertEqual(decoded.timers.map(\.title), ["Focus"])
        XCTAssertEqual(decoded.appLimits.map(\.appName), ["Editor"])
        XCTAssertNil(decoded.workspace)
    }

    func testAIPacketPresetRoundTripsWithWorkspaceSelection() throws {
        var store = SchedStore.empty
        let preset = SchedAIPacketPreset(name: "Release packet", request: "What should I finish?", includeWorkspace: true)
        store.aiPacketPresets = [preset]
        let encoded = try JSONEncoder().encode(store)
        let decoded = try JSONDecoder().decode(SchedStore.self, from: encoded)
        XCTAssertEqual(decoded.aiPacketPresets, [preset])
    }

    @MainActor
    func testCalendarPanelBuildsWithoutConstraintException() {
        let controller = CalendarPanelController()
        XCTAssertFalse(controller.view.subviews.isEmpty)
    }
}

private extension JSONDecoder {
    static var schedPacket: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct LegacyAlarm: Codable {
    let id: UUID
    let title: String
    let note: String
    let fireAt: Date
    let level: InterventionLevel
    let action: SchedAction
    let repeatDaily: Bool
    let enabled: Bool
}
