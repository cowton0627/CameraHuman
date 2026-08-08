import UIKit
import XCTest

/// Lightweight visual regression checks for stable, non-camera screens.
///
/// To intentionally refresh baselines, run the UI test with
/// `SNAPSHOT_RECORD_PATH` set to `CameraHumanUITests/Snapshots`, review the
/// generated PNGs, and commit only the reviewed images.
final class VisualRegressionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    func test_stableScreensMatchBaselines() throws {
        try assertSnapshot(named: "media-empty") {
            let media = app.buttons["dock.media"]
            XCTAssertTrue(media.waitForExistence(timeout: 5))
            media.tap()
            XCTAssertTrue(app.staticTexts["media.empty"].waitForExistence(timeout: 5))
        }

        try assertSnapshot(named: "assistant") {
            let assistant = app.buttons["dock.assistant"]
            XCTAssertTrue(assistant.waitForExistence(timeout: 5))
            assistant.tap()
            XCTAssertTrue(app.staticTexts["assistant.title"].waitForExistence(timeout: 5))
        }

        try assertSnapshot(named: "settings") {
            let settings = app.buttons["dock.settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            settings.tap()
            XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: 5))
        }
    }

    private func assertSnapshot(
        named name: String,
        after action: () -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        action()
        let screenshot = app.screenshot()
        let image = screenshot.image

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "actual-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)

        if let recordPath = ProcessInfo.processInfo.environment["SNAPSHOT_RECORD_PATH"] {
            let directory = URL(fileURLWithPath: recordPath, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let data = image.pngData() else {
                XCTFail("Could not encode snapshot: \(name)", file: file, line: line)
                return
            }
            try data.write(to: directory.appendingPathComponent("\(name).png"), options: .atomic)
            return
        }

        guard let baselineURL = Bundle(for: Self.self).url(forResource: name, withExtension: "png"),
              let baseline = UIImage(contentsOfFile: baselineURL.path) else {
            let generatedURL = URL(fileURLWithPath: "/tmp/CameraHumanSnapshots", isDirectory: true)
                .appendingPathComponent("\(name).png")
            try? FileManager.default.createDirectory(at: generatedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? image.pngData()?.write(to: generatedURL, options: .atomic)
            XCTFail("Missing visual baseline Snapshots/\(name).png", file: file, line: line)
            return
        }

        let result = compare(image, with: baseline)
        XCTAssertLessThanOrEqual(
            result.mismatchedPixelRatio,
            0.005,
            "Visual difference for \(name): \(String(format: "%.2f", result.mismatchedPixelRatio * 100))% of pixels (max channel delta \(result.maximumChannelDelta))",
            file: file,
            line: line
        )
    }

    private func compare(_ actual: UIImage, with baseline: UIImage) -> (mismatchedPixelRatio: Double, maximumChannelDelta: Int) {
        guard let actualPixels = PixelBuffer(image: actual), let baselinePixels = PixelBuffer(image: baseline),
              actualPixels.width == baselinePixels.width, actualPixels.height == baselinePixels.height else {
            return (1, 255)
        }

        var mismatched = 0
        var maximumDelta = 0
        for index in stride(from: 0, to: actualPixels.bytes.count, by: 4) {
            let delta = max(
                abs(Int(actualPixels.bytes[index]) - Int(baselinePixels.bytes[index])),
                abs(Int(actualPixels.bytes[index + 1]) - Int(baselinePixels.bytes[index + 1])),
                abs(Int(actualPixels.bytes[index + 2]) - Int(baselinePixels.bytes[index + 2]))
            )
            maximumDelta = max(maximumDelta, delta)
            if delta > 12 {
                mismatched += 1
            }
        }
        return (Double(mismatched) / Double(actualPixels.width * actualPixels.height), maximumDelta)
    }
}

private struct PixelBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init?(image: UIImage) {
        guard let cgImage = image.cgImage, let context = CGContext(
            data: nil,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: cgImage.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = context.data else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        width = cgImage.width
        height = cgImage.height
        bytes = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: cgImage.width * cgImage.height * 4))
    }
}
