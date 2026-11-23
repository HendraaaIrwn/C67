import XCTest

final class HiFiPreviewUITests: XCTestCase {
    @MainActor func testTripCompletionKeepsDoneAccessible() {
        let app = XCUIApplication()
        app.launchArguments = ["--completed-trip-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-AppleInterfaceStyle", "Dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Trip complete"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Done"].isHittable)
        XCTAssertTrue(app.buttons["tripReturnToStartingPoint"].isHittable)
    }

    @MainActor func testNavigationAndArrivalControlsAreVisible() {
        let app = XCUIApplication()
        app.launchArguments = ["--active-trip-preview", "-AppleInterfaceStyle", "Light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["450 m"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["tripRouteInstruction"].isHittable)
        let stop = app.staticTexts["tripCurrentStop"]
        XCTAssertTrue(stop.isHittable)
        XCTAssertLessThan(stop.frame.maxY, app.staticTexts["450 m"].frame.minY)
        let gps = app.staticTexts["Waiting for GPS"]
        let retry = app.buttons["Try again"]
        XCTAssertTrue(gps.isHittable && retry.isHittable)
        XCTAssertEqual(gps.frame.midY, retry.frame.midY, accuracy: 3)
        XCTAssertLessThan(gps.frame.maxX, retry.frame.minX)
        XCTAssertTrue(app.buttons["Navigate with Apple Maps"].isHittable)
        XCTAssertTrue(app.buttons["Back to trip"].isHittable)
        let arrive = app.buttons["confirmTripArrival"]
        let back = app.buttons["Back to trip"]
        XCTAssertTrue(arrive.isHittable)
        XCTAssertGreaterThanOrEqual(arrive.frame.height, 44)
        XCTAssertEqual(arrive.frame.midY, back.frame.midY, accuracy: 2)
        XCTAssertLessThan(app.scrollViews["tripProgressPanel"].frame.height, app.frame.height * 0.45)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "TRIP STARTED - refactored design"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate()

        app.launchArguments = ["--arrival-preview", "-AppleInterfaceStyle", "Light"]
        app.launch()
        XCTAssertTrue(app.staticTexts["You’ve arrived"].waitForExistence(timeout: 10))
        let planned = app.staticTexts["arrivalPlannedVisitWindow"]
        XCTAssertTrue(planned.isHittable)
        XCTAssertNotNil(planned.label.range(of: #"^\d{2}\.\d{2}–\d{2}\.\d{2}$"#, options: .regularExpression))
        XCTAssertLessThan(planned.frame.maxY, app.staticTexts["tripCurrentStop"].frame.minY)
        XCTAssertTrue(app.buttons["completeTripVisit"].isHittable)
        captureArrival(app)
    }

    @MainActor private func captureArrival(_ app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Arrival — planned visit time range"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testNavigationActionsRemainReachableAtAccessibilitySize() {
        let app = XCUIApplication()
        app.launchArguments = ["--active-trip-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Route from starting point"].waitForExistence(timeout: 10))
        for identifier in ["Navigate with Apple Maps", "confirmTripArrival", "Back to trip"] {
            let button = app.buttons[identifier]
            for _ in 0 ..< 8 where !button.isHittable { app.scrollViews["tripProgressPanel"].swipeUp() }
            XCTAssertTrue(button.isHittable, "\(identifier) should remain reachable")
        }
    }

    @MainActor func testNewSketchStatesRender() {
        let arguments = ["--add-places-preview", "--add-places-selected-preview", "--places-sheet-preview",
                         "--home-added-preview", "--saved-trip-preview", "--active-trip-preview", "--arrival-preview", "--save-name-preview"]
        for argument in arguments {
            let app = XCUIApplication()
            app.launchArguments = [argument, "-AppleInterfaceStyle", "Light"]
            app.launch()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
            let expected = argument == "--arrival-preview" ? "You’ve arrived" : argument == "--active-trip-preview" ? "Route from starting point" : nil
            if let expected { XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 5)) }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = argument
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    @MainActor func testAddPlacesAccessibleReadingWidth() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--add-places-preview", "-AppleInterfaceStyle", "Light"]
        app.launch()
        XCTAssertTrue(app.buttons["addPlacesNext"].waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(app.buttons["addPlacesNext"].frame.width, 640)
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .trait, .textClipped])
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "ADD PLACES - Reading width and accessibility"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor func testArrivalAtAccessibilitySizeInDarkAppearance() {
        let app = XCUIApplication()
        app.launchArguments = ["--arrival-preview", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL", "-AppleInterfaceStyle", "Dark"]
        app.launch()
        XCTAssertTrue(app.staticTexts["You’ve arrived"].waitForExistence(timeout: 10))
        let complete = app.buttons["completeTripVisit"]
        for _ in 0 ..< 12 {
            if complete.exists && complete.isHittable { break }
            app.scrollViews["tripProgressPanel"].swipeUp()
        }
        XCTAssertTrue(complete.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Arrival - Dark Accessibility XXXL"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
