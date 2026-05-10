import Foundation

/// Chat 對話引擎介面。當前用本地 keyword 比對；之後接 AI（Gemini / Claude / on-device FM）只要換實作。
protocol ChatEngine {
    func reply(to input: String) -> String
}

/// 本地 keyword 比對 + 取狀態樣板。沒網路、零 token 成本，但回答只有套版，不真懂。
final class KeywordChatEngine: ChatEngine {
    private let settings: CameraSettingsStore
    private let planner: ShotPlannerStore
    private let mediaLibrary: MediaLibrary

    init(
        settings: CameraSettingsStore = .shared,
        planner: ShotPlannerStore = .shared,
        mediaLibrary: MediaLibrary = .shared
    ) {
        self.settings = settings
        self.planner = planner
        self.mediaLibrary = mediaLibrary
    }

    func reply(to input: String) -> String {
        let normalized = input.lowercased()

        if normalized.contains("設定") || normalized.contains("config") {
            return currentSettingsSummary()
        }

        if normalized.contains("素材") || normalized.contains("media") || normalized.contains("錄影") {
            return latestMediaSummary()
        }

        if normalized.contains("建議") || normalized.contains("下一步") || normalized.contains("next") {
            let suggestion = nextStepSuggestion()
            planner.addActionItem(suggestion)
            return "\(suggestion)\n\n已加入 action items。"
        }

        return [
            currentSettingsSummary(),
            latestMediaSummary(),
            nextStepSuggestion()
        ].joined(separator: "\n\n")
    }

    private func currentSettingsSummary() -> String {
        "目前設定：\(settings.videoPreset.displayTitle)、\(settings.aspectRatio.displayTitle)、啟動鏡頭 \(settings.startupCamera.displayTitle)、格線 \(settings.showGrid ? "開啟" : "關閉")。"
    }

    private func latestMediaSummary() -> String {
        let recordings = (try? mediaLibrary.listRecordings()) ?? []
        guard let latest = recordings.first else {
            return "目前還沒有素材。先到 Camera 錄一段，Media 頁就會出現可播放的檔案。"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        let timeString = formatter.string(from: latest.createdAt)
        let sizeFormatter = ByteCountFormatter()
        sizeFormatter.countStyle = .file
        let sizeText = sizeFormatter.string(fromByteCount: latest.fileSize)
        return "最近素材：\(latest.fileName)\n建立時間 \(timeString)\n檔案大小 \(sizeText)"
    }

    private func nextStepSuggestion() -> String {
        let recordings = (try? mediaLibrary.listRecordings()) ?? []

        if recordings.isEmpty {
            return "下一步建議：先在 Camera 頁用 \(settings.videoPreset.displayTitle) / \(settings.aspectRatio.displayTitle) 錄一段測試，確認構圖框、鏡頭切換與聲音監看都正常。"
        }

        if settings.aspectRatio == .ratio4x3 {
            return "下一步建議：你現在走 4:3 流程，錄完後去 Media 確認輸出比例是否正確，再決定是否要補更完整的裁切安全區。"
        }

        return "下一步建議：Media 已經有素材，現在應該開始補 Chat 與 Media 的素材註記、分類或專案管理，不要再把流程卡在單純錄影。"
    }
}
