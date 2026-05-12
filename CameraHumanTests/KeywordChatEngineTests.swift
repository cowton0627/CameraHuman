//
//  KeywordChatEngineTests.swift
//  CameraHumanTests
//

import XCTest
@testable import CameraHuman

// MARK: - Stubs / Spies

private final class StubCameraSettings: CameraSettings {
    var videoPreset: CameraSettingsStore.VideoPreset = .fullHD
    var aspectRatio: CameraSettingsStore.AspectRatio = .ratio16x9
    var startupCamera: CameraSettingsStore.StartupCamera = .back
    var showGrid: Bool = true
}

private final class StubMediaLibrary: MediaLibraryReading {
    var recordingsToReturn: [MediaRecording] = []
    var errorToThrow: Error?

    func listRecordings() throws -> [MediaRecording] {
        if let errorToThrow {
            throw errorToThrow
        }
        return recordingsToReturn
    }
}

private final class SpyShotPlanner: ShotPlanner {
    private(set) var addedActionItems: [String] = []

    func addActionItem(_ value: String) {
        addedActionItems.append(value)
    }
}

// MARK: - Helpers

private func makeRecording(name: String = "test.mov", createdAt: Date = Date()) -> MediaRecording {
    let url = URL(fileURLWithPath: "/tmp/\(name)")
    return MediaRecording(
        url: url,
        fileName: name,
        createdAt: createdAt,
        fileSize: 12_345,
        note: ""
    )
}

private func makeEngine(
    settings: StubCameraSettings = StubCameraSettings(),
    planner: SpyShotPlanner = SpyShotPlanner(),
    mediaLibrary: StubMediaLibrary = StubMediaLibrary()
) -> (KeywordChatEngine, StubCameraSettings, SpyShotPlanner, StubMediaLibrary) {
    let engine = KeywordChatEngine(settings: settings, planner: planner, mediaLibrary: mediaLibrary)
    return (engine, settings, planner, mediaLibrary)
}

// MARK: - Tests

final class KeywordChatEngineTests: XCTestCase {

    // 1. 「設定」中文 keyword → 回傳設定摘要，含預期欄位
    func test_replyToSettingsKeyword_returnsSettingsSummary() {
        let (engine, settings, _, _) = makeEngine()
        settings.videoPreset = .fullHD
        settings.aspectRatio = .ratio16x9
        settings.startupCamera = .back
        settings.showGrid = true

        let reply = engine.reply(to: "目前設定")

        XCTAssertTrue(reply.contains("FHD"), "應包含 videoPreset displayTitle")
        XCTAssertTrue(reply.contains("16:9"), "應包含 aspectRatio displayTitle")
        XCTAssertTrue(reply.contains("Back"), "應包含 startupCamera displayTitle")
        XCTAssertTrue(reply.contains("開啟"), "showGrid=true 應顯示「開啟」")
    }

    // 2. 「config」英文 keyword 也算設定 → 同樣回 settings summary
    func test_replyToConfigKeyword_returnsSettingsSummary() {
        let (engine, _, _, _) = makeEngine()

        let reply = engine.reply(to: "what's the config?")

        XCTAssertTrue(reply.contains("目前設定"))
    }

    // 3. 大小寫不敏感（內部 lowercased）
    func test_replyIsCaseInsensitive() {
        let (engine, _, _, _) = makeEngine()

        let reply = engine.reply(to: "CONFIG 一下")

        XCTAssertTrue(reply.contains("目前設定"))
    }

    // 4. 「素材」+ 沒錄影 → 提示「目前還沒有素材」
    func test_replyToMediaKeyword_whenNoRecordings_returnsEmptyState() {
        let (engine, _, _, media) = makeEngine()
        media.recordingsToReturn = []

        let reply = engine.reply(to: "最近素材")

        XCTAssertTrue(reply.contains("目前還沒有素材"))
    }

    // 5. 「素材」+ 有錄影 → 包含檔名
    func test_replyToMediaKeyword_whenHasRecordings_includesFileName() {
        let (engine, _, _, media) = makeEngine()
        media.recordingsToReturn = [
            makeRecording(name: "CameraHuman-20260512-153000.mov")
        ]

        let reply = engine.reply(to: "看一下最近素材")

        XCTAssertTrue(reply.contains("CameraHuman-20260512-153000.mov"))
    }

    // 6. 「media」英文 keyword 也算素材
    func test_replyToMediaKeyword_english() {
        let (engine, _, _, media) = makeEngine()
        media.recordingsToReturn = [makeRecording()]

        let reply = engine.reply(to: "show me the media")

        XCTAssertTrue(reply.contains("最近素材"))
    }

    // 7. 「錄影」也算素材 keyword
    func test_replyToRecordingKeyword_returnsMediaSummary() {
        let (engine, _, _, _) = makeEngine()

        let reply = engine.reply(to: "錄影檔在哪")

        XCTAssertTrue(reply.contains("目前還沒有素材"))
    }

    // 8. 「下一步建議」+ 沒錄影 → 提示先錄一段測試
    func test_replyToSuggestionKeyword_whenNoRecordings_recommendsRecording() {
        let (engine, _, planner, media) = makeEngine()
        media.recordingsToReturn = []

        let reply = engine.reply(to: "下一步建議")

        XCTAssertTrue(reply.contains("先在 Camera"))
        XCTAssertTrue(reply.contains("錄一段測試"))
        XCTAssertEqual(planner.addedActionItems.count, 1, "「建議」分支應該把建議加進 action items")
    }

    // 9. 「建議」+ 有錄影 + 16:9 → 提示補註記分類
    func test_replyToSuggestionKeyword_withRecordings_and16x9_recommendsOrganizing() {
        let (engine, settings, _, media) = makeEngine()
        settings.aspectRatio = .ratio16x9
        media.recordingsToReturn = [makeRecording()]

        let reply = engine.reply(to: "建議")

        XCTAssertTrue(reply.contains("Media 已經有素材"))
        XCTAssertTrue(reply.contains("註記"))
    }

    // 10. 「建議」+ 有錄影 + 4:3 → 提示 4:3 流程
    func test_replyToSuggestionKeyword_withRecordings_and4x3_recommends4x3Flow() {
        let (engine, settings, _, media) = makeEngine()
        settings.aspectRatio = .ratio4x3
        media.recordingsToReturn = [makeRecording()]

        let reply = engine.reply(to: "下一步")

        XCTAssertTrue(reply.contains("4:3 流程"))
    }

    // 11. 「next」英文 keyword 也算建議
    func test_replyToNextKeyword_english() {
        let (engine, _, planner, _) = makeEngine()

        _ = engine.reply(to: "what's next?")

        XCTAssertEqual(planner.addedActionItems.count, 1)
    }

    // 12. 完全不匹配 → fallback 回三合一摘要
    func test_replyToUnknownInput_returnsFallbackSummary() {
        let (engine, _, _, media) = makeEngine()
        media.recordingsToReturn = [makeRecording()]

        let reply = engine.reply(to: "Hello there")

        XCTAssertTrue(reply.contains("目前設定"), "fallback 應含 settings 摘要")
        XCTAssertTrue(reply.contains("最近素材"), "fallback 應含 media 摘要")
        XCTAssertTrue(reply.contains("下一步建議"), "fallback 應含 next-step 摘要")
    }

    // 13. fallback 路徑「不」會 addActionItem
    func test_fallbackBranch_doesNotAddActionItem() {
        let (engine, _, planner, _) = makeEngine()

        _ = engine.reply(to: "Hello there")

        XCTAssertTrue(planner.addedActionItems.isEmpty, "fallback 路徑不該寫 action item")
    }

    // 14. listRecordings throw → media summary fallback「沒有素材」（try? 吃掉 error）
    func test_replyToMediaKeyword_whenListRecordingsThrows_treatsAsEmpty() {
        let (engine, _, _, media) = makeEngine()
        media.errorToThrow = NSError(domain: "test", code: -1)

        let reply = engine.reply(to: "最近素材")

        XCTAssertTrue(reply.contains("目前還沒有素材"))
    }

    // 15. 「建議」分支：addActionItem 被呼叫且內容含建議文字
    func test_suggestionBranch_recordsActionItemWithSuggestionText() {
        let (engine, _, planner, _) = makeEngine()

        _ = engine.reply(to: "下一步")

        XCTAssertEqual(planner.addedActionItems.count, 1)
        XCTAssertTrue(planner.addedActionItems[0].contains("下一步建議"))
    }
}
