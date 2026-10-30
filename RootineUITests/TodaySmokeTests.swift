import XCTest

/// iPhone UI smoke tests (TESTING.md §8): a few seconds each, on an in-memory store seeded with a scenario and
/// a clock frozen at 09:30 on Friday 2026-10-30. Elements are found by accessibility identifier.
@MainActor
final class TodaySmokeTests: XCTestCase {
    private let timeout: TimeInterval = 5

    override func setUp() {
        continueAfterFailure = false
    }

    /// `layout` overrides the remembered layout for this launch; `nil` uses whatever was saved last.
    private func launch(_ seed: String?, layout: String? = "byTime", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [
            "-RootineInMemoryStore", "-RootineNoRelay",
            "-RootineFixedNow", "2026-10-30T09:30", "-RootineTimeZone", "America/Los_Angeles",
        ]
        if let seed {
            arguments += ["-RootineSeed", seed]
        }
        if let layout {
            arguments += ["-todayLayout", layout]
        }
        app.launchArguments = arguments + extra
        app.launch()
        return app
    }

    private func row(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["row.\(name)"]
    }

    /// Waits for `element`, scrolling the list down if it isn't on screen yet (lists only build visible rows).
    @discardableResult
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: timeout) {
            return true
        }
        for _ in 0 ..< 5 where !element.exists {
            app.swipeUp()
        }
        return element.waitForExistence(timeout: 1)
    }

    private func detail(_ name: String, in app: XCUIApplication) -> String {
        app.staticTexts["row.\(name).detail"].label
    }

    /// 1
    func testEmptyStoreThenAddADailyHabit() {
        let app = launch(nil)
        XCTAssertTrue(app.staticTexts["No Items Yet"].waitForExistence(timeout: timeout))

        app.buttons["today.addButton"].tap()
        let save = app.buttons["editor.save"]
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        XCTAssertFalse(save.isEnabled, "An unnamed item can't be saved")
        let name = app.textFields["editor.name"]
        name.tap()
        name.typeText("Morning walk")
        XCTAssertTrue(save.isEnabled)
        save.tap()

        XCTAssertTrue(row("Morning walk", in: app).waitForExistence(timeout: timeout))
    }

    /// 2
    func testCheckOffAHabitAndUncheckIt() {
        let app = launch("typicalDay")
        let control = app.buttons["row.Floss.control"]
        XCTAssertTrue(reveal(control, in: app))
        XCTAssertEqual(control.label, "Mark done")
        control.tap()
        XCTAssertEqual(control.label, "Mark not done")
        control.tap()
        XCTAssertEqual(control.label, "Mark done")
    }

    /// 3
    func testCountedItemTapsAndUndoesASteps() {
        let app = launch("countedHeavy")
        let control = app.buttons["row.Water.control"]
        XCTAssertTrue(control.waitForExistence(timeout: timeout))
        XCTAssertEqual(detail("Water", in: app), "3 / 8 glasses")
        control.tap()
        control.tap()
        XCTAssertEqual(detail("Water", in: app), "5 / 8 glasses")

        row("Water", in: app).swipeLeft()
        app.buttons["Undo"].tap()
        XCTAssertEqual(detail("Water", in: app), "4 / 8 glasses")
    }

    /// 4
    func testLayoutSwitchIsRememberedAcrossLaunches() {
        var app = launch("typicalDay", layout: nil)
        app.buttons["today.layoutMenu"].tap()
        app.buttons["Category"].tap()
        XCTAssertTrue(app.staticTexts["Health"].waitForExistence(timeout: timeout))

        app.terminate()
        app = launch("typicalDay", layout: nil)
        XCTAssertTrue(app.staticTexts["Health"].waitForExistence(timeout: timeout))
        XCTAssertFalse(app.staticTexts["Morning"].exists, "Still in the Time of Day layout")

        // Leave the saved layout as the other tests expect it.
        app.buttons["today.layoutMenu"].tap()
        app.buttons["Time of Day"].tap()
    }

    /// 5
    func testEditingAnItemRenamesIt() {
        let app = launch("typicalDay")
        let edit = app.buttons["row.Read.edit"]
        XCTAssertTrue(reveal(edit, in: app))
        edit.tap()

        let name = app.textFields["editor.name"]
        XCTAssertTrue(name.waitForExistence(timeout: timeout))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8) + "Read fiction")
        app.buttons["editor.save"].tap()

        XCTAssertTrue(row("Read fiction", in: app).waitForExistence(timeout: timeout))
        XCTAssertFalse(row("Read", in: app).exists)
    }

    /// 6
    func testDeletingAnItemRemovesIt() {
        let app = launch("typicalDay")
        let edit = app.buttons["row.Floss.edit"]
        XCTAssertTrue(reveal(edit, in: app))
        edit.tap()

        let delete = app.buttons["editor.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: timeout))
        delete.tap()
        let confirm = app.buttons["editor.confirmDelete"].firstMatch
        if confirm.waitForExistence(timeout: 2) {
            confirm.tap()
        } else {
            app.sheets.buttons["Delete Item"].firstMatch.tap()
        }

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: timeout))
        XCTAssertFalse(row("Floss", in: app).waitForExistence(timeout: 1))
    }

    /// 7
    func testOverdueItemsComeFirstAtTheFixedClock() {
        let app = launch("overdue", layout: "byUrgency")
        let names = ["Call the bank", "Renew passport", "Vitamins", "Stretch", "Lunch walk"]
        XCTAssertTrue(row(names[0], in: app).waitForExistence(timeout: timeout))
        let tops = names.map { row($0, in: app).frame.minY }
        XCTAssertEqual(tops, tops.sorted(), "Expected \(names) top to bottom")

        XCTAssertTrue(detail("Vitamins", in: app).hasPrefix("Overdue"))
        XCTAssertTrue(detail("Call the bank", in: app).hasPrefix("Due "))
        XCTAssertFalse(detail("Lunch walk", in: app).hasPrefix("Overdue"))
    }

    /// 8
    func testTimesPerWeekItemAlreadyMetIsNotListed() {
        let app = launch("everyPattern")
        XCTAssertTrue(reveal(row("2× a week", in: app), in: app))
        XCTAssertFalse(row("3× a week (met)", in: app).exists)
    }

    /// 9
    /// Launches into test mode itself (a local test store, not in-memory), so this leaves the simulator in test
    /// mode; switch back in Settings when using that simulator by hand.
    func testTestModeShowsTheBannerAndResetUndoesChanges() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-RootineTestMode", "typicalDay", "-RootineNoRelay", "-todayLayout", "byTime",
            "-RootineFixedNow", "2026-10-30T09:30", "-RootineTimeZone", "America/Los_Angeles",
        ]
        app.launch()

        let banner = app.buttons["testModeBanner"]
        XCTAssertTrue(banner.waitForExistence(timeout: timeout))
        let control = app.buttons["row.Stretch.control"]
        XCTAssertTrue(control.waitForExistence(timeout: timeout))
        control.tap()
        XCTAssertEqual(control.label, "Mark not done")

        banner.tap()
        app.buttons["Reset Test Data"].tap()
        // Resetting rebuilds the list on the fresh store, which closes Settings.
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.buttons["row.Stretch.control"].waitForExistence(timeout: timeout))
        XCTAssertEqual(app.buttons["row.Stretch.control"].label, "Mark done")
    }
}
