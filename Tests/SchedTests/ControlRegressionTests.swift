import XCTest
@testable import Sched

final class ControlRegressionTests: XCTestCase {
    func testBottomFadeKeepsAConstantVisualDepth() {
        let compact = SchedBottomFadeMetrics.locations(viewportHeight: 160)
        let wide = SchedBottomFadeMetrics.locations(viewportHeight: 320)
        let compactDepth = (compact[2].doubleValue - compact[1].doubleValue) * 160
        let wideDepth = (wide[2].doubleValue - wide[1].doubleValue) * 320
        XCTAssertEqual(compactDepth, SchedBottomFadeMetrics.depth, accuracy: 0.01)
        XCTAssertEqual(wideDepth, SchedBottomFadeMetrics.depth, accuracy: 0.01)
    }

    func testAlertGestureOnlyCountsMovementTowardTheNearestEdge() {
        XCTAssertEqual(SchedAlertGestureMetrics.outwardDistance(deltaX: 80, rightEdge: true), 80)
        XCTAssertEqual(SchedAlertGestureMetrics.outwardDistance(deltaX: -80, rightEdge: true), 0)
        XCTAssertEqual(SchedAlertGestureMetrics.outwardDistance(deltaX: -80, rightEdge: false), 80)
        XCTAssertEqual(SchedAlertGestureMetrics.swipeProgress(deltaX: 200, rightEdge: true), 1)
        XCTAssertEqual(SchedAlertGestureMetrics.swipeThreshold, 32)
        XCTAssertEqual(SchedAlertGestureMetrics.intentDelay, 0.12, accuracy: 0.001)
        XCTAssertEqual(SchedAlertGestureMetrics.holdDuration, 0.42, accuracy: 0.001)
    }

    @MainActor
    func testExplicitHourStylesAreDeterministic() {
        XCTAssertTrue(SchedTimeFormat.resolvedUses24Hour(.twentyFourHour))
        XCTAssertFalse(SchedTimeFormat.resolvedUses24Hour(.twelveHour))
    }

    @MainActor
    func testCustomNavigationAndCardsExposeButtonAccessibility() {
        let navigation = SchedNavItem(section: .calendar)
        XCTAssertEqual(navigation.accessibilityRole(), .button)
        XCTAssertEqual(navigation.accessibilityLabel(), "Calendar")
        XCTAssertEqual(navigation.accessibilityIdentifier(), "navigation.calendar")

        let alarm = SchedAlarm(
            title: "Review the launch checklist",
            fireAt: Date(timeIntervalSince1970: 1_800_000_000),
            level: .focus
        )
        let card = SchedAlarmCard(alarm: alarm, selected: false)
        XCTAssertEqual(card.accessibilityRole(), .button)
        XCTAssertTrue(card.accessibilityLabel()?.contains(alarm.title) == true)
        XCTAssertEqual(card.accessibilityIdentifier(), alarm.id.uuidString)
    }

    @MainActor
    func testLightCanvasControlsUseAquaAppearance() {
        let button = SchedGhostButton("Test", action: #selector(NSWindow.performZoom(_:)), target: nil)
        XCTAssertEqual(button.appearance?.name, .aqua)
    }

    @MainActor
    func testSelfMessageAlertExplainsItsSourceToVoiceOver() {
        let bubble = SchedMessageBubble(
            title: "Stand up",
            detail: "Past you requested a stretch.",
            side: .incoming,
            fill: .white
        )
        XCTAssertEqual(bubble.accessibilityRole(), .group)
        XCTAssertEqual(
            bubble.accessibilityLabel(),
            "Stand up. Past you requested a stretch."
        )
    }
}
