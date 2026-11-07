import XCTest

/// Places (DATA.md phase 3a): saving a place and linking an item to it, on the same in-memory store and frozen
/// clock as `TodaySmokeTests`. Location itself is off with an in-memory store; visits are covered by unit tests
/// and the device checklist (TESTING.md §10.10).
@MainActor
final class PlacesSmokeTests: XCTestCase {
    private let timeout: TimeInterval = 5

    override func setUp() {
        continueAfterFailure = false
    }

    private func snapshot(_ name: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// 10
    func testSaveAPlaceAndLinkAnItemToIt() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-RootineInMemoryStore", "-RootineNoRelay", "-RootineSeed", "typicalDay", "-todayLayout", "byTime",
            "-RootineFixedNow", "2026-10-30T09:30", "-RootineTimeZone", "America/Los_Angeles",
        ]
        app.launch()

        app.buttons["today.settingsButton"].tap()
        let places = app.buttons["settings.places"]
        XCTAssertTrue(places.waitForExistence(timeout: timeout))
        places.tap()
        let add = app.buttons["places.add"]
        XCTAssertTrue(add.waitForExistence(timeout: timeout))
        snapshot("Places", of: app)
        add.tap()

        let save = app.buttons["place.save"]
        XCTAssertTrue(save.waitForExistence(timeout: timeout))
        XCTAssertFalse(save.isEnabled, "An unnamed place can't be saved")
        let name = app.textFields["place.name"]
        name.tap()
        name.typeText("Gym")
        XCTAssertTrue(save.isEnabled)
        snapshot("New place", of: app)
        save.tap()
        XCTAssertTrue(app.buttons["place.Gym"].waitForExistence(timeout: timeout))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()
        let edit = app.buttons["row.Read.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: timeout))
        edit.tap()
        let link = app.buttons["editor.placeLink"]
        for _ in 0 ..< 5 where !link.isHittable {
            app.swipeUp()
        }
        link.tap()
        app.buttons["Gym"].tap()
        snapshot("Place link", of: app)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(link.waitForExistence(timeout: timeout))
        XCTAssertEqual(link.label, "Place, Gym · visit of 30 min")
        snapshot("Editor", of: app)
        app.buttons["editor.save"].tap()
        XCTAssertTrue(app.buttons["row.Read.edit"].waitForExistence(timeout: timeout))
    }
}
