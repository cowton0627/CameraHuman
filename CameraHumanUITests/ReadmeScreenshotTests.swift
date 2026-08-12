import XCTest

/// Captures the screenshots used in README.md.
///
/// Deliberately separate from `VisualRegressionTests`: those compare against committed
/// baselines and are restricted to stable, non-camera screens. This one includes the
/// camera screen — which never renders a preview on the simulator — so it must not
/// become a regression baseline.
///
/// Regenerate with `scripts/capture_readme_screenshots.sh`, then review the PNGs in
/// `docs/screenshots/` before committing them.
///
/// The screenshots are recovered from the result bundle's attachments rather than
/// written straight to disk. `xcodebuild test FOO=bar` sets a *build setting*, and even
/// `TEST_RUNNER_FOO=bar` did not reach this process on Xcode 26 — so the env-var route
/// silently produced nothing. Attachments always survive, so the script exports those.
final class ReadmeScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func test_captureReadmeScreenshots() throws {
        // The Camera screen is deliberately *not* captured. Under `-ui-testing` the app
        // disables camera hardware and prints "Camera hardware disabled for UI tests"
        // over the HUD, so any shot taken here advertises the test harness rather than
        // the product. That screen needs a real device; see README.
        try tapDock("media", waitingFor: app.staticTexts["media.empty"])
        capture(named: "media")

        try tapDock("assistant", waitingFor: app.staticTexts["assistant.title"])
        capture(named: "assistant")

        try tapDock("settings", waitingFor: app.staticTexts["settings.title"])
        capture(named: "settings")
    }

    private func tapDock(_ item: String, waitingFor element: XCUIElement) throws {
        let button = app.buttons["dock.\(item)"]
        XCTAssertTrue(
            button.waitForExistence(timeout: UITestTimeout.standard),
            "dock.\(item) never appeared"
        )
        button.tap()
        XCTAssertTrue(
            element.waitForExistence(timeout: UITestTimeout.standard),
            "\(item) screen did not settle"
        )
    }

    /// The attachment name is the contract with `scripts/capture_readme_screenshots.sh`,
    /// which matches on everything before the first underscore.
    private func capture(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
