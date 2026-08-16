import XCTest

final class TaskTrackerWatchOSUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()
    }

    func testTimerStartShowsInlinePauseAndStopwatchPage() throws {
        // ActiveTimerScreen is the first page of the root vertical-page TabView.
        let start = app.buttons["Start timer"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // List-row countdown with inline pause while running.
        let display = app.staticTexts["timer.display"]
        XCTAssertTrue(display.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["timer.inlinePause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Stop timer"].waitForExistence(timeout: 5))

        // Swipe the nested horizontal pager (start from the countdown, inside the pager) to the
        // analog stopwatch page.
        display.swipeLeft()
        XCTAssertTrue(
            app.descendants(matching: .any)["timer.stopwatchDial"].waitForExistence(timeout: 5)
        )
    }
}
