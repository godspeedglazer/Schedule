import Foundation
import XCTest
@testable import Keen

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

        let store = try JSONDecoder().decode(KeenStore.self, from: json)
        XCTAssertTrue(store.menuBarShowIcon)
        XCTAssertFalse(store.menuBarShowDate)
        XCTAssertTrue(store.menuBarShowTime)
        XCTAssertFalse(store.menuBarShowSeconds)
        XCTAssertFalse(store.menuBarShowNextCountdown)
        XCTAssertFalse(store.repeatSoundOnAlert)
        XCTAssertEqual(store.hourStyle, .system)
        XCTAssertTrue(store.showAMPM)
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
        let alarm = try JSONDecoder().decode(KeenAlarm.self, from: data)
        XCTAssertFalse(alarm.isTimer)
        XCTAssertNil(alarm.pausedRemainingSeconds)
    }

    func testPausedTimerRoundTrips() throws {
        let original = KeenAlarm(
            title: "Focus",
            fireAt: .now,
            level: .gentle,
            enabled: false,
            isTimer: true,
            pausedRemainingSeconds: 317
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(KeenAlarm.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testAppWatchUsesExactBundleOrExecutableIdentity() {
        let watch = KeenAppWatch(
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
        XCTAssertEqual(KeenTextLimits.clean(oversized, limit: KeenTextLimits.title).count, KeenTextLimits.title)
        XCTAssertFalse(KeenTextLimits.clean("  Useful title  ", limit: KeenTextLimits.title).hasPrefix(" "))
    }

    @MainActor
    func testCalendarPanelBuildsWithoutConstraintException() {
        let controller = CalendarPanelController()
        XCTAssertFalse(controller.view.subviews.isEmpty)
    }
}

private struct LegacyAlarm: Codable {
    let id: UUID
    let title: String
    let note: String
    let fireAt: Date
    let level: InterventionLevel
    let action: KeenAction
    let repeatDaily: Bool
    let enabled: Bool
}
