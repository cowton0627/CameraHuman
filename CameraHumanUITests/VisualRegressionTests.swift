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
            XCTAssertTrue(media.waitForExistence(timeout: UITestTimeout.standard))
            media.tap()
            XCTAssertTrue(app.staticTexts["media.empty"].waitForExistence(timeout: UITestTimeout.standard))
        }

        try assertSnapshot(named: "assistant") {
            let assistant = app.buttons["dock.assistant"]
            XCTAssertTrue(assistant.waitForExistence(timeout: UITestTimeout.standard))
            assistant.tap()
            XCTAssertTrue(app.staticTexts["assistant.title"].waitForExistence(timeout: UITestTimeout.standard))
        }

        try assertSnapshot(named: "settings") {
            let settings = app.buttons["dock.settings"]
            XCTAssertTrue(settings.waitForExistence(timeout: UITestTimeout.standard))
            settings.tap()
            XCTAssertTrue(app.staticTexts["settings.title"].waitForExistence(timeout: UITestTimeout.standard))
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
            result.clusteredMismatchRatio,
            Self.maximumClusteredMismatchRatio,
            """
            Visual difference for \(name): \
            \(String(format: "%.3f", result.clusteredMismatchRatio * 100))% of pixels differ in solid blocks \
            (raw per-pixel difference \(String(format: "%.2f", result.rawMismatchRatio * 100))%, \
            max channel delta \(result.maximumChannelDelta))
            """,
            file: file,
            line: line
        )
    }

    /// A pixel counts as different when any channel differs by more than this.
    private static let channelTolerance = 12

    /// Only pixels whose whole (2r+1)×(2r+1) neighbourhood also differs are
    /// counted. Text anti-aliasing differs by a 1–2px fringe along glyph edges,
    /// so it does not survive this erosion; a moved or missing element does.
    private static let clusterRadius = 2

    /// Measured anti-aliasing noise between a locally recorded baseline and CI
    /// was 0.034% and 0.023% across two runs — this leaves ~6× headroom.
    private static let maximumClusteredMismatchRatio = 0.002

    private func compare(
        _ actual: UIImage,
        with baseline: UIImage
    ) -> (clusteredMismatchRatio: Double, rawMismatchRatio: Double, maximumChannelDelta: Int) {
        guard let actualPixels = PixelBuffer(image: actual), let baselinePixels = PixelBuffer(image: baseline),
              actualPixels.width == baselinePixels.width, actualPixels.height == baselinePixels.height else {
            return (1, 1, 255)
        }

        let width = actualPixels.width
        let height = actualPixels.height
        let total = width * height

        var differs = [Bool](repeating: false, count: total)
        var rawMismatched = 0
        var maximumDelta = 0

        for pixel in 0..<total {
            let index = pixel * 4
            let delta = max(
                abs(Int(actualPixels.bytes[index]) - Int(baselinePixels.bytes[index])),
                abs(Int(actualPixels.bytes[index + 1]) - Int(baselinePixels.bytes[index + 1])),
                abs(Int(actualPixels.bytes[index + 2]) - Int(baselinePixels.bytes[index + 2]))
            )
            maximumDelta = max(maximumDelta, delta)
            if delta > Self.channelTolerance {
                differs[pixel] = true
                rawMismatched += 1
            }
        }

        let radius = Self.clusterRadius
        var clustered = 0
        if width > 2 * radius, height > 2 * radius {
            for y in radius..<(height - radius) {
                for x in radius..<(width - radius) where differs[y * width + x] {
                    var solid = true
                    neighbourhood: for dy in -radius...radius {
                        let row = (y + dy) * width
                        for dx in -radius...radius where !differs[row + x + dx] {
                            solid = false
                            break neighbourhood
                        }
                    }
                    if solid {
                        clustered += 1
                    }
                }
            }
        }

        return (Double(clustered) / Double(total), Double(rawMismatched) / Double(total), maximumDelta)
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
