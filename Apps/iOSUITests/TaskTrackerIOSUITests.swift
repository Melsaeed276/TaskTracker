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
