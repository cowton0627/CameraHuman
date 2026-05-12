//
//  CameraSettingsStoreTests.swift
//  CameraHumanTests
//

import XCTest
import AVFoundation
@testable import CameraHuman

final class CameraSettingsStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test-settings-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private func makeStore() -> CameraSettingsStore {
        CameraSettingsStore(defaults: defaults)
    }

    // 1. 空 defaults → videoPreset 等於 .hd（rawValue 0 → enum first case）
    // 注意：這是現況行為，不是「想要的 default」。如果想要 fullHD 為 default，要改 init 邏輯。
    func test_defaults_videoPresetIsHD() {
        let store = makeStore()
        XCTAssertEqual(store.videoPreset, .hd)
    }

    // 2. 空 defaults → aspectRatio == .ratio16x9
    func test_defaults_aspectRatioIs16x9() {
        let store = makeStore()
        XCTAssertEqual(store.aspectRatio, .ratio16x9)
    }

    // 3. 空 defaults → startupCamera == .back
    func test_defaults_startupCameraIsBack() {
        let store = makeStore()
        XCTAssertEqual(store.startupCamera, .back)
    }

    // 4. 空 defaults → showGrid == true（init 有顯式 nil-check）
    func test_defaults_showGridIsTrue() {
        let store = makeStore()
        XCTAssertTrue(store.showGrid)
    }

    // 5. 設 videoPreset → didSet persist 到 defaults
    func test_setVideoPreset_persists() {
        let store = makeStore()
        store.videoPreset = .fullHD
        XCTAssertEqual(defaults.integer(forKey: "camera_settings_video_preset"), CameraSettingsStore.VideoPreset.fullHD.rawValue)
    }

    // 6. 設 aspectRatio → didSet persist
    func test_setAspectRatio_persists() {
        let store = makeStore()
        store.aspectRatio = .ratio4x3
        XCTAssertEqual(defaults.integer(forKey: "camera_settings_aspect_ratio"), CameraSettingsStore.AspectRatio.ratio4x3.rawValue)
    }

    // 7. 設 startupCamera → didSet persist
    func test_setStartupCamera_persists() {
        let store = makeStore()
        store.startupCamera = .front
        XCTAssertEqual(defaults.integer(forKey: "camera_settings_startup_camera"), CameraSettingsStore.StartupCamera.front.rawValue)
    }

    // 8. 設 showGrid → didSet persist
    func test_setShowGrid_persists() {
        let store = makeStore()
        store.showGrid = false
        XCTAssertFalse(defaults.bool(forKey: "camera_settings_show_grid"))
    }

    // 9. Persist + 重建 store 後狀態保留
    func test_persistAndReload_preservesState() {
        let store1 = makeStore()
        store1.videoPreset = .fullHD
        store1.aspectRatio = .ratio4x3
        store1.startupCamera = .front
        store1.showGrid = false

        let store2 = CameraSettingsStore(defaults: defaults)
        XCTAssertEqual(store2.videoPreset, .fullHD)
        XCTAssertEqual(store2.aspectRatio, .ratio4x3)
        XCTAssertEqual(store2.startupCamera, .front)
        XCTAssertFalse(store2.showGrid)
    }

    // 10. 任一 setter 都觸發 .cameraSettingsDidChange 通知
    func test_setVideoPreset_postsNotification() {
        let store = makeStore()
        let expectation = expectation(forNotification: .cameraSettingsDidChange, object: nil)
        store.videoPreset = .fullHD
        wait(for: [expectation], timeout: 0.5)
    }

    // 11. showGrid 切換也觸發通知
    func test_setShowGrid_postsNotification() {
        let store = makeStore()
        let expectation = expectation(forNotification: .cameraSettingsDidChange, object: nil)
        store.showGrid = false
        wait(for: [expectation], timeout: 0.5)
    }

    // 12. VideoPreset.displayTitle / capturePreset 對應
    func test_videoPreset_titlesAndPresets() {
        XCTAssertEqual(CameraSettingsStore.VideoPreset.hd.displayTitle, "HD")
        XCTAssertEqual(CameraSettingsStore.VideoPreset.fullHD.displayTitle, "FHD")
        XCTAssertEqual(CameraSettingsStore.VideoPreset.hd.capturePreset, .hd1280x720)
        XCTAssertEqual(CameraSettingsStore.VideoPreset.fullHD.capturePreset, .hd1920x1080)
    }

    // 13. AspectRatio.landscapeSize 對應
    func test_aspectRatio_landscapeSize() {
        XCTAssertEqual(CameraSettingsStore.AspectRatio.ratio16x9.landscapeSize, CGSize(width: 16, height: 9))
        XCTAssertEqual(CameraSettingsStore.AspectRatio.ratio4x3.landscapeSize, CGSize(width: 4, height: 3))
    }

    // 14. StartupCamera.capturePosition 對應
    func test_startupCamera_capturePosition() {
        XCTAssertEqual(CameraSettingsStore.StartupCamera.back.capturePosition, .back)
        XCTAssertEqual(CameraSettingsStore.StartupCamera.front.capturePosition, .front)
    }
}
