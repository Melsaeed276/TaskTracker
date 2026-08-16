import XCTest

@MainActor
final class TaskTrackerMacOSUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()
    }

    func testMenuBarQuickAddShowsTaskInPanel() throws {
        openMenuBarPanel()

        let field = app.textFields["menubar.today.newTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("Menu bar regression task\n")

        XCTAssertTrue(
            app.buttons["Open details for Menu bar regression task"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["Run Menu bar regression task"].exists)
    }

    func testMenuBarCircleTapCompletesTask() throws {
        openMenuBarPanel()

        let field = app.textFields["menubar.today.newTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("Circle tap regression task\n")

        let completeButton = app.buttons["Circle tap regression task, Mark complete"]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.click()

        XCTAssertTrue(
            app.buttons["Circle tap regression task, Mark incomplete"].waitForExistence(timeout: 5)
        )
    }

    func testMenuBarTitleTapOpensInlineDetailsAndSaves() throws {
        openMenuBarPanel()

        let field = app.textFields["menubar.today.newTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("Details tap regression task\n")

        let detailsButton = app.buttons["Open details for Details tap regression task"]
        XCTAssertTrue(detailsButton.waitForExistence(timeout: 5))
        detailsButton.click()

        // Details cover the whole menu-bar panel — no separate Tasks window, and the Today
        // quick-add / tab chrome are replaced by the full editor (date, priority, timer).
        XCTAssertFalse(app.windows["Tasks"].waitForExistence(timeout: 2))
        XCTAssertTrue(
            app.descendants(matching: .any)["menubar.today.editCover"].waitForExistence(timeout: 5)
                || app.staticTexts["Edit Task"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(app.textFields["menubar.today.newTaskField"].exists)

        let titleField = app.textFields["menubar.today.editForm.titleField"]
        XCTAssertTrue(
            titleField.waitForExistence(timeout: 5)
                || app.textFields["Title"].waitForExistence(timeout: 2),
            "Expected the inline details title field after tapping the task name"
        )
        let editableTitle = titleField.exists ? titleField : app.textFields["Title"]
        XCTAssertEqual(editableTitle.value as? String, "Details tap regression task")

        let saveButton = app.buttons["menubar.today.editForm.saveButton"]
        let saveFallback = app.buttons["Save"]
        XCTAssertTrue(
            saveButton.waitForExistence(timeout: 3) || saveFallback.waitForExistence(timeout: 2),
            "Expected Save in the details editor"
        )

        editableTitle.click()
        editableTitle.typeKey("a", modifierFlags: .command)
        editableTitle.typeText("Renamed via details tap")

        (saveButton.exists ? saveButton : saveFallback).click()

        XCTAssertTrue(
            app.buttons["Open details for Renamed via details tap"].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(editableTitle.waitForExistence(timeout: 2))
    }

    func testMenuBarRunButtonStartsTimer() throws {
        openMenuBarPanel()

        let field = app.textFields["menubar.today.newTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("Run button regression task\n")

        let runButton = app.buttons["Run Run button regression task"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 5))
        XCTAssertTrue(runButton.isEnabled)
        runButton.click()

        // Run switches to the Timer tab with an active session.
        XCTAssertFalse(field.waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Pause timer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Stop timer"].exists)
        XCTAssertFalse(app.buttons["Start timer"].isEnabled)
    }

    func testOpenTasksOpensTaskHubWindow() throws {
        openMenuBarPanel()

        let openTasksButton = app.buttons["menubar.openTasksButton"]
        XCTAssertTrue(openTasksButton.waitForExistence(timeout: 5))
        openTasksButton.click()

        let taskHubWindow = app.windows["Tasks"]
        XCTAssertTrue(taskHubWindow.waitForExistence(timeout: 5))
        // A custom .accessibilityIdentifier on a NavigationSplitView gets absorbed into SwiftUI's
        // own internal identifier on macOS rather than exposed as-is (confirmed via the captured
        // accessibility hierarchy: it reports as "task-hub, SidebarNavigationSplitView", not
        // "taskHub.root") — a SwiftUI limitation for this container type, not an app bug. Verify
        // real, reliably-present sidebar content instead of that identifier.
        XCTAssertTrue(taskHubWindow.staticTexts["Today"].waitForExistence(timeout: 5))
    }

    func testTaskHubCheckboxCompletesTask() throws {
        openMenuBarPanel()

        let field = app.textFields["menubar.today.newTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("Hub checkbox regression task\n")

        let openTasksButton = app.buttons["menubar.openTasksButton"]
        XCTAssertTrue(openTasksButton.waitForExistence(timeout: 5))
        openTasksButton.click()

        let taskHubWindow = app.windows["Tasks"]
        XCTAssertTrue(taskHubWindow.waitForExistence(timeout: 5))

        let completeButton = taskHubWindow.buttons[
            "Hub checkbox regression task, Mark complete"
        ]
        XCTAssertTrue(completeButton.waitForExistence(timeout: 5))
        completeButton.click()

        XCTAssertTrue(
            taskHubWindow.buttons["Hub checkbox regression task, Mark incomplete"]
                .waitForExistence(timeout: 5)
        )
    }

    func testMenuBarHasNoSettingsButton() throws {
        // Settings moved into the app itself (Tasks window toolbar + the standard app-menu
        // Settings… item) — the bar panel must not have its own Settings control anymore.
        openMenuBarPanel()
        XCTAssertFalse(app.buttons["menubar.preferencesButton"].waitForExistence(timeout: 2))
    }

    func testTaskHubToolbarSettingsButtonOpensSettingsWindow() throws {
        openMenuBarPanel()

        let openTasksButton = app.buttons["menubar.openTasksButton"]
        XCTAssertTrue(openTasksButton.waitForExistence(timeout: 5))
        openTasksButton.click()

        let taskHubWindow = app.windows["Tasks"]
        XCTAssertTrue(taskHubWindow.waitForExistence(timeout: 5))

        let settingsButton = taskHubWindow.buttons["taskHub.settingsButton"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.click()

        let settingsWindow = app.windows["TaskTracker Settings"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        // Form's AX role isn't `.other`, match by identifier generically (same reasoning as the
        // NavigationSplitView identifier issue found earlier this session).
        XCTAssertTrue(app.descendants(matching: .any)["preferences.form"].waitForExistence(timeout: 5))
    }

    func testMenuBarPanelTabsSwitchBetweenTodayAndTimer() throws {
        openMenuBarPanel()

        let field = app.textFields["menubar.today.newTaskField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText("Tab switch regression task\n")

        let taskRow = app.buttons["Open details for Tab switch regression task"]
        XCTAssertTrue(taskRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Run Tab switch regression task"].exists)

        selectMenuBarPanelTab("Timer")

        XCTAssertFalse(field.waitForExistence(timeout: 2))
        XCTAssertFalse(taskRow.waitForExistence(timeout: 1))
        XCTAssertTrue(app.buttons["Start timer"].waitForExistence(timeout: 5))

        selectMenuBarPanelTab("Today")

        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertTrue(taskRow.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start timer"].waitForExistence(timeout: 1))
    }

    func testMenuBarPanelDefaultsToTimerTabWhenTimerIsActive() throws {
        openMenuBarPanel()

        XCTAssertTrue(app.textFields["menubar.today.newTaskField"].waitForExistence(timeout: 5))

        selectMenuBarPanelTab("Timer")
        let startButton = app.buttons["Start timer"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.click()

        // Status item label flips from idle → running once the timer starts; toggle the panel closed
        // then open again so MenuBarPanel re-runs its one-shot initial-tab check.
        closeMenuBarPanel()
        openMenuBarPanel(preferringActiveTimer: true)

        XCTAssertTrue(app.buttons["Start timer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Stop timer"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["menubar.today.newTaskField"].waitForExistence(timeout: 2))
    }

    func testRightClickStatusItemShowsQuitAndTerminatesApp() throws {
        let statusItem = app.statusItems["TaskTracker"]
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        statusItem.rightClick()

        let quitItem = app.menuItems["Quit TaskTracker"]
        XCTAssertTrue(quitItem.waitForExistence(timeout: 5))
        quitItem.click()

        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    func testMenuBarTimerListRowInlinePause() throws {
        openMenuBarPanel()
        selectMenuBarPanelTab("Timer")

        let startButton = app.buttons["Start timer"]
        XCTAssertTrue(startButton.waitForExistence(timeout: 5))
        startButton.click()

        // List-row countdown + inline pause on the menu-bar panel (no analog dial there).
        XCTAssertTrue(app.staticTexts["timer.display"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["timer.inlinePause"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["timer.stopwatchDial"].exists)
    }

    func testTaskHubTimerPagerShowsStopwatchDial() throws {
        openMenuBarPanel()

        let openTasksButton = app.buttons["menubar.openTasksButton"]
        XCTAssertTrue(openTasksButton.waitForExistence(timeout: 5))
        openTasksButton.click()

        let taskHubWindow = app.windows["Tasks"]
        XCTAssertTrue(taskHubWindow.waitForExistence(timeout: 5))

        selectTaskHubSection("Timer", in: taskHubWindow)

        // Timer pane defaults to the list-row page with the countdown display.
        XCTAssertTrue(taskHubWindow.staticTexts["timer.display"].waitForExistence(timeout: 5))

        // Switch to the stopwatch page via the dot button (macOS has no swipe pager).
        let stopwatchDot = taskHubWindow.buttons["timer.pageDot.stopwatch"]
        XCTAssertTrue(stopwatchDot.waitForExistence(timeout: 5))
        stopwatchDot.click()

        XCTAssertTrue(
            taskHubWindow.descendants(matching: .any)["timer.stopwatchDial"].waitForExistence(timeout: 5)
        )
    }

    private func openMenuBarPanel(preferringActiveTimer: Bool = false) {
        if preferringActiveTimer {
            let running = app.statusItems["Timer running"]
            if running.waitForExistence(timeout: 3) {
                running.click()
                return
            }
            let paused = app.statusItems["Timer paused"]
            if paused.waitForExistence(timeout: 1) {
                paused.click()
                return
            }
        }

        // Idle state now shows the real app icon (accessibilityLabel "TaskTracker"), not a
        // timer-state SF Symbol — see MenuBarStatusLabel.
        let statusByLabel = app.statusItems["TaskTracker"]
        if statusByLabel.waitForExistence(timeout: 3) {
            statusByLabel.click()
            return
        }

        let fallback = app.statusItems.firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 5))
        fallback.click()
    }

    private func closeMenuBarPanel() {
        // Second click on the status item dismisses a `.window`-style MenuBarExtra.
        let running = app.statusItems["Timer running"]
        if running.exists {
            running.click()
            return
        }
        let paused = app.statusItems["Timer paused"]
        if paused.exists {
            paused.click()
            return
        }
        let idle = app.statusItems["TaskTracker"]
        if idle.exists {
            idle.click()
            return
        }
        app.statusItems.firstMatch.click()
    }

    private func selectMenuBarPanelTab(_ title: String) {
        let picker = app.segmentedControls["menubar.panel.tabPicker"]
        if picker.waitForExistence(timeout: 5) {
            let segment = picker.buttons[title]
            XCTAssertTrue(segment.waitForExistence(timeout: 5))
            segment.click()
            return
        }

        // Some macOS SwiftUI builds expose segmented pickers as radio buttons instead.
        let radio = app.radioButtons[title]
        XCTAssertTrue(radio.waitForExistence(timeout: 5), "Expected tab '\(title)' in segmented control or radio group")
        radio.click()
    }

    private func selectTaskHubSection(_ title: String, in window: XCUIElement) {
        // Sidebar rows in a selectable List surface as buttons on some macOS builds and as
        // static text on others — try the button first, then fall back to the label text.
        let button = window.buttons[title].firstMatch
        if button.waitForExistence(timeout: 3) {
            button.click()
            return
        }

        let text = window.staticTexts[title].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5), "Expected sidebar section '\(title)'")
        text.click()
    }
}
