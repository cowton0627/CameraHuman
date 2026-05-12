//
//  CameraDiagnosticsTests.swift
//  CameraHumanTests
//

import XCTest
import AVFoundation
@testable import CameraHuman

final class CameraDiagnosticsTests: XCTestCase {

    private func makeInputs(
        recordingState: String = "IDLE",
        quality: String = "FHD",
        aspect: String = "16:9",
        lensTitle: String? = "1x",
        position: AVCaptureDevice.Position = .back,
        device: AVCaptureDevice? = nil,
        audioAuthorized: Bool = true,
        audioTrackCount: Int = 1
    ) -> CameraDiagnostics.Inputs {
        CameraDiagnostics.Inputs(
            recordingState: recordingState,
            quality: quality,
            aspect: aspect,
            lensTitle: lensTitle,
            position: position,
            device: device,
            audioAuthorized: audioAuthorized,
            audioTrackCount: audioTrackCount
        )
    }

    // 1. 輸出固定 5 行
    func test_report_alwaysHasFiveLines() {
        let report = CameraDiagnostics.report(from: makeInputs())
        XCTAssertEqual(report.components(separatedBy: "\n").count, 5)
    }

    // 2. position == .back → "BACK"
    func test_report_backPosition_showsBack() {
        let report = CameraDiagnostics.report(from: makeInputs(position: .back))
        XCTAssertTrue(report.contains("BACK"))
        XCTAssertFalse(report.contains("FRONT"))
    }

    // 3. position == .front → "FRONT"
    func test_report_frontPosition_showsFront() {
        let report = CameraDiagnostics.report(from: makeInputs(position: .front))
        XCTAssertTrue(report.contains("FRONT"))
    }

    // 4. lensTitle nil → "--"
    func test_report_nilLens_showsDoubleDash() {
        let report = CameraDiagnostics.report(from: makeInputs(lensTitle: nil))
        XCTAssertTrue(report.contains("Lens       -- ·"))
    }

    // 5. lensTitle set → 包含 title
    func test_report_withLensTitle_includesTitle() {
        let report = CameraDiagnostics.report(from: makeInputs(lensTitle: "0.5x"))
        XCTAssertTrue(report.contains("Lens       0.5x · BACK"))
    }

    // 6. device nil → resolution "--"
    func test_report_nilDevice_showsDoubleDashResolution() {
        let report = CameraDiagnostics.report(from: makeInputs(device: nil))
        XCTAssertTrue(report.contains("Resolution --"))
    }

    // 7. audioAuthorized false → "OFF · 0 tracks"
    func test_report_audioNotAuthorized_showsOffAndZeroTracks() {
        let report = CameraDiagnostics.report(from: makeInputs(audioAuthorized: false, audioTrackCount: 0))
        XCTAssertTrue(report.contains("Mic        OFF · 0 tracks"))
    }

    // 8. audioAuthorized true + trackCount 0 → 內部 max 拉到 1 → "1 track" 單數
    func test_report_audioAuthorizedButZeroTracks_pinsTo1Track() {
        let report = CameraDiagnostics.report(from: makeInputs(audioAuthorized: true, audioTrackCount: 0))
        XCTAssertTrue(report.contains("Mic        ON · 1 track"), "授權但 trackCount=0 時應 floor to 1")
        XCTAssertFalse(report.contains("1 tracks"), "1 應為單數，不可有 's'")
    }

    // 9. trackCount 2 → "2 tracks" 複數
    func test_report_multipleTracks_usesPlural() {
        let report = CameraDiagnostics.report(from: makeInputs(audioAuthorized: true, audioTrackCount: 2))
        XCTAssertTrue(report.contains("Mic        ON · 2 tracks"))
    }

    // 10. Quality + Aspect 合成
    func test_report_qualityAndAspect_combinedInLine() {
        let report = CameraDiagnostics.report(from: makeInputs(quality: "HD", aspect: "4:3"))
        XCTAssertTrue(report.contains("Quality    HD · 4:3"))
    }

    // 11. recordingState 帶入第一行
    func test_report_recordingState_reflectedInFirstLine() {
        let report = CameraDiagnostics.report(from: makeInputs(recordingState: "RECORDING"))
        let firstLine = report.components(separatedBy: "\n").first ?? ""
        XCTAssertEqual(firstLine, "Recording  RECORDING")
    }

    // 12. 全段行序：Recording → Quality → Lens → Resolution → Mic
    func test_report_lineOrder() {
        let report = CameraDiagnostics.report(from: makeInputs())
        let lines = report.components(separatedBy: "\n")
        XCTAssertTrue(lines[0].hasPrefix("Recording"))
        XCTAssertTrue(lines[1].hasPrefix("Quality"))
        XCTAssertTrue(lines[2].hasPrefix("Lens"))
        XCTAssertTrue(lines[3].hasPrefix("Resolution"))
        XCTAssertTrue(lines[4].hasPrefix("Mic"))
    }
}
