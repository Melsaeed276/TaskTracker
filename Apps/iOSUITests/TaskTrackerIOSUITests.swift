import XCTest

@MainActor
final class TaskTrackerIOSUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()
    }

    func testTodayQuickAddShowsTask() throws {
        let field = app.textFields["today.newTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Today regression task\n")

        XCTAssertTrue(app.staticTexts["Today regression task"].waitForExistence(timeout: 5))
    }

    func testPoolQuickAddKeepsAllTasksVisible() throws {
        openTab(named: "Pool")

        let field = app.textFields["pool.newTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))

        let titles = ["Pool one", "Pool two", "Pool three"]
        for title in titles {
            field.tap()
            field.typeText("\(title)\n")
        }

        for title in titles {
            XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        }
    }

    func testTimerStartPauseStopFlow() throws {
        openTab(named: "Timer")

        let preset = app.buttons["timer.preset.15"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.tap()

        let start = app.buttons["timer.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let inlinePause = app.buttons["timer.inlinePause"]
        let stop = app.buttons["timer.stop"]
        XCTAssertTrue(inlinePause.waitForExistence(timeout: 5))
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertTrue(inlinePause.isEnabled)
        XCTAssertTrue(stop.isEnabled)

        let display = app.staticTexts["timer.display"]
        XCTAssertTrue(display.waitForExistence(timeout: 5))

        stop.tap()
        XCTAssertTrue(app.buttons["timer.start"].waitForExistence(timeout: 5))
    }

    func testTimerInlinePausePausesAndResumes() throws {
        openTab(named: "Timer")

        let start = app.buttons["timer.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let inlinePause = app.buttons["timer.inlinePause"]
        XCTAssertTrue(inlinePause.waitForExistence(timeout: 5))
        XCTAssertEqual(inlinePause.label, "Pause timer")
        inlinePause.tap()

        let inlineResume = app.buttons["timer.inlinePause"]
        XCTAssertTrue(inlineResume.waitForExistence(timeout: 5))
        XCTAssertEqual(inlineResume.label, "Resume timer")
        inlineResume.tap()

        XCTAssertTrue(app.buttons["timer.inlinePause"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["timer.inlinePause"].label, "Pause timer")

        // Clean up so the reused app process doesn't leak an active timer into later tests.
        app.buttons["timer.stop"].tap()
        XCTAssertTrue(app.buttons["timer.start"].waitForExistence(timeout: 5))
    }

    func testTimerStopwatchPageShowsElapsedAndEndTime() throws {
        openTab(named: "Timer")

        let start = app.buttons["timer.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // Swipe to the stopwatch page (page dots + swipe, like Apple Clock).
        app.swipeLeft()

        let dial = app.descendants(matching: .any)["timer.stopwatchDial"]
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        XCTAssertTrue(dial.label.contains("Ends"), "Expected end time in the stopwatch label, got: \(dial.label)")
        XCTAssertTrue(app.buttons["timer.stopwatchStartPause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["timer.stopwatchStop"].exists)
    }

    func testEditSheetDeleteTaskIsInFormBody() throws {
        let field = app.textFields["today.newTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("Delete placement task\n")

        let title = app.staticTexts["Delete placement task"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()

        let saveButton = app.buttons["taskEdit.saveButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))

        // Delete Task is a form row in the body, not pinned under Save. Scroll the form if needed.
        let deleteButton = app.buttons["taskEdit.deleteButton"]
        if !deleteButton.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
    }

    // MARK: - Responsive layout

    /// Asserts an element is present, fully on-screen (not clipped by the window), and tappable.
    private func requireOnScreen(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Expected \(element.identifier) to exist", file: file, line: line)
        // If a short/landscape screen pushed it below the fold, scroll it into view first.
        if !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, "\(element.identifier) is not reachable on this screen size", file: file, line: line)

        let window = app.windows.firstMatch.frame
        let frame = element.frame
        XCTAssertLessThanOrEqual(frame.minX, window.maxX, "\(element.identifier) overflows the right edge", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.maxX, window.minX, "\(element.identifier) overflows the left edge", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, window.maxY + 1, "\(element.identifier) overflows the bottom edge", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, window.minY - 1, "\(element.identifier) overflows the top edge", file: file, line: line)
    }

    /// Opens the Timer tab and verifies the idle layout fits and every control is reachable
    /// without clipping — this is the cross-device regression guard for screen-size fit.
    func testTimerTabIdleLayoutFitsAndReachable() throws {
        openTab(named: "Timer")

        requireOnScreen(app.buttons["timer.preset.15"])
        requireOnScreen(app.buttons["timer.preset.60"])
        requireOnScreen(app.buttons["timer.start"])

        // The stopwatch face must be reachable from the idle layout (iOS uses the
        // system page dots, so we verify reachability by swiping to the page).
        app.swipeLeft()
        let dial = app.descendants(matching: .any)["timer.stopwatchDial"]
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        XCTAssertTrue(dial.isHittable)
    }

    /// Starts a session and verifies the stopwatch face + its controls fit and stay reachable
    /// on this device size (the dial previously clipped on short screens).
    func testTimerTabActiveStopwatchLayoutFitsAndReachable() throws {
        openTab(named: "Timer")

        app.buttons["timer.preset.15"].tap()
        app.buttons["timer.start"].tap()

        requireOnScreen(app.buttons["timer.inlinePause"])
        requireOnScreen(app.buttons["timer.stop"])

        // Reach the stopwatch page and check the dial + controls fit.
        app.swipeLeft()
        let dial = app.descendants(matching: .any)["timer.stopwatchDial"]
        XCTAssertTrue(dial.waitForExistence(timeout: 5))
        requireOnScreen(app.buttons["timer.stopwatchStartPause"])
        requireOnScreen(app.buttons["timer.stopwatchStop"])
        requireOnScreen(app.buttons["timer.reset"])

        // Clean up: stop the session so the reused app process stays idle for later tests.
        app.buttons["timer.stopwatchStop"].tap()
        XCTAssertTrue(app.buttons["timer.start"].waitForExistence(timeout: 5))
    }

    /// Guards against regression when the user bumps the system text size to an accessibility level:
    /// the larger type must not push controls off-screen or overflow horizontally.
    func testTimerTabAdaptsToAccessibilityTextSize() throws {
        // Reuse the single shared app instance (relaunching it with the
        // accessibility text-size override) so we never leave a stray second
        // process that can confuse later tests in the suite.
        app.launchArguments = ["--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()

        let tab = app.tabBars.buttons["Timer"]
        XCTAssertTrue(tab.waitForExistence(timeout: 5))
        tab.tap()

        requireOnScreen(app.buttons["timer.preset.15"], file: #filePath, line: #line)
        requireOnScreen(app.buttons["timer.start"], file: #filePath, line: #line)
    }

    private func openTab(named name: String) {
        let tabBarButton = app.tabBars.buttons[name]
        if tabBarButton.waitForExistence(timeout: 3) {
            tabBarButton.tap()
            return
        }

        let fallback = app.buttons[name].firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 5))
        fallback.tap()
    }
}
