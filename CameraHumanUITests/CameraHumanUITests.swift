import XCTest

final class CameraHumanUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    private func tapDock(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: UITestTimeout.standard), "Missing dock button: \(identifier)", file: file, line: line)
        XCTAssertTrue(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: button)],
                timeout: UITestTimeout.standard
            ) == .completed,
            "Dock button is not hittable: \(identifier)",
            file: file,
            line: line
        )
        button.tap()
    }

    func test_launchShowsCameraControls() {
        XCTAssertTrue(app.buttons["camera.record"].waitForExistence(timeout: UITestTimeout.standard))
        XCTAssertTrue(app.buttons["camera.switch"].exists)
        XCTAssertTrue(app.buttons["camera.diagnostics"].exists)
    }

    func test_dockNavigatesAcrossAllScreens() {
        tapDock("dock.media")
        XCTAssertTrue(app.staticTexts["media.title"].waitForExistence(timeout: UITestTimeout.standard))

        tapDock("dock.assistant")
        XCTAssertTrue(app.staticTexts["assistant.title"].waitForExistence(timeout: UITestTimeout.standard))

        tapDock("dock.settings")
        XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: UITestTimeout.standard))

        tapDock("dock.camera")
        XCTAssertTrue(app.buttons["camera.record"].waitForExistence(timeout: UITestTimeout.standard))
    }

    func test_mediaEmptyStateReturnsToCamera() {
        tapDock("dock.media")
        XCTAssertTrue(app.staticTexts["media.empty"].waitForExistence(timeout: UITestTimeout.standard))

        app.buttons["media.openCamera"].tap()
        XCTAssertTrue(app.buttons["camera.record"].waitForExistence(timeout: UITestTimeout.standard))
    }

    func test_assistantQuickActionProducesReply() {
        tapDock("dock.assistant")
        let quickAction = app.buttons["assistant.quickAction.目前設定"]
        XCTAssertTrue(quickAction.waitForExistence(timeout: UITestTimeout.standard))
        quickAction.tap()

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "目前設定")).firstMatch.waitForExistence(timeout: UITestTimeout.standard))
    }

    func test_settingsChangePersistsAcrossNavigation() {
        tapDock("dock.settings")
        let aspectControl = app.segmentedControls["settings.aspectRatio"]
        XCTAssertTrue(aspectControl.waitForExistence(timeout: UITestTimeout.standard))
        aspectControl.buttons["4:3"].tap()

        tapDock("dock.assistant")
        tapDock("dock.settings")

        XCTAssertTrue(aspectControl.buttons["4:3"].isSelected)
    }
}
