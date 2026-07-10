import XCTest
@testable import Keen

final class ControlRegressionTests: XCTestCase {
    @MainActor
    func testSnoozeMenuDisplaysRealDurations() {
        let button = KeenSnoozeButton(defaultMinutes: 7) { _ in }
        let titles = button.itemTitles
        XCTAssertTrue(titles.contains("5 minutes"))
        XCTAssertTrue(titles.contains("7 minutes"))
        XCTAssertTrue(titles.contains("60 minutes"))
        XCTAssertFalse(titles.contains("(minutes) minutes"))
    }

    @MainActor
    func testExplicitHourStylesAreDeterministic() {
        XCTAssertTrue(SchedTimeFormat.resolvedUses24Hour(.twentyFourHour))
        XCTAssertFalse(SchedTimeFormat.resolvedUses24Hour(.twelveHour))
    }
}
