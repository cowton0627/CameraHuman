# CameraHuman

`CameraHuman` 是一個以 `UIKit + AVFoundation` 為主的 iOS 拍攝工具原型。主軸不是單純相機 demo，而是把拍攝、音訊監看、素材管理、拍攝規劃整成同一個工作流。

## Current App Structure

底部自製 dock（不是 `UITabBar` 預設樣式）分成四頁：

- `Camera`
  拍攝頁。整合相機預覽、錄影、鏡頭切換、音訊電平監看、格式資訊與技術 HUD。
- `Media`
  已錄製素材列表，支援播放、滑動刪除、素材註記，以及把某支素材 link 到 planner。
- `Chat`
  拍攝助理頁。本地 keyword 對話引擎 + shot checklist + 備忘 + action items。
- `Settings`
  拍攝偏好：錄影畫質、比例、啟動鏡頭、格線。

## Implemented Features

### Camera

- 服務層拆分：
  - `CameraSession` 管 `AVCaptureSession`、鏡頭枚舉、前後鏡頭切換、權限請求
  - `CameraRecorder` 管錄影狀態機（idle / starting / recording / stopping）+ `AVCaptureFileOutputRecordingDelegate` + 計時器
  - `AudioLevelMonitor` 用 timer 輪詢 `AVCaptureConnection` 的 audio channels
- 後鏡頭依硬體實際支援列出 0.5x / 1x / 3x，不做假鏡頭
- 前鏡頭只暴露單一 front mode，不硬做多焦段假象
- 上方拍攝 HUD
  - 第一排：`FORMAT` / `FRAME` / `TIME`（錄影中變 `REC`）
  - 第二排：`LENS` / `FPS` / `SHUTTER` / `IRIS` / `ISO` / `WB`
- 錄影鍵 + 狀態機，過渡期間自動禁用避免重複點擊
- 即時音量監看（綠 / 黃 / 紅三段顏色 + dB 數值）
- `i` 診斷資訊（5 行精簡狀態 + 可複製）
- `16:9` / `4:3` 構圖框與遮罩
- 錄影完成 toast
- 最近一次錄影刪除捷徑

### Media

- 錄影檔儲存到 `Documents/Recordings`
- 列表顯示檔名 + 建立時間 + 檔案大小 + 註記
- 點開可播放 `.mov`
- 滑動 row 露出 Delete / Note / Link
- `4:3` 模式錄影在儲存時做輸出裁切（`MediaLibrary` 內）

### Chat

- 三顆 quick action button：目前設定 / 最近素材 / 下一步建議
- Planner 卡片：shot checklist（44pt 觸控區）/ 備忘 / 儲存 / linked clip / action items
- 對話引擎走 `ChatEngine` 協定，目前實作為本地 keyword 比對；未來換 AI 只要換實作
- 鍵盤避讓：點空白 / 拖列表 / Return key 都會收下鍵盤

### Settings

- `HD` / `FHD`
- `16:9` / `4:3`
- 預設前鏡頭 / 後鏡頭
- 顯示格線

## Tech Stack

純 UIKit + AVFoundation，沒用 SwiftUI / Combine / async-await。

- `UIKit` — 所有 UI
- `AVFoundation` — capture session、錄影、音訊
- `AVKit` — 素材播放（`AVPlayerViewController`）
- `Foundation` — `UserDefaults`、`NotificationCenter`、`FileManager`
- `CoreGraphics` — App icon 生成 script

Persistence 走 `UserDefaults` + `Documents/Recordings/` + JSON metadata，不用 CoreData。
最低部署 iOS 13.0。

## Architecture at a Glance

- **Service layer**：`CameraSession` / `CameraRecorder` / `AudioLevelMonitor` 包住所有 `AVCapture*` 物件，VC 不直接接觸 AVFoundation
- **Closure-based callback**：service 不暴露 protocol delegate，用 `onConfigured` / `onStateChange` 等 closure 通知 VC
- **Singleton + NotificationCenter pub/sub**：`CameraSettingsStore` / `MediaLibrary` / `ShotPlannerStore` 三個全域 store
- **Strategy（`ChatEngine` 協定）**：`KeywordChatEngine` 為預設實作，未來換 AI 不改 VC
- **State machine**：`CameraRecorder.State`（idle → starting → recording → stopping → idle）
- **Custom view encapsulation**：`AspectMaskView` / `AudioMeterCardView` / `ToastView` / `PlannerCardView`

每個選擇的「為什麼」見 [`DECISIONS.md`](./DECISIONS.md)。

## Project Structure

`project.pbxproj` 採用 Xcode 16 同步資料夾（`PBXFileSystemSynchronizedRootGroup`），加新檔到對應資料夾就會自動納入 build，不必手動編輯 `pbxproj`。

```
CameraHuman/
├── App/                                   入口
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   └── RootTabBarController.swift         自製 dock + 自動切換 portrait/landscape
├── Camera/
│   ├── CameraViewController.swift         view 組裝 + service callback wiring
│   ├── CameraSession.swift                AVCaptureSession + 鏡頭管理
│   ├── CameraRecorder.swift               錄影狀態機 + delegate
│   ├── AudioLevelMonitor.swift            音量輪詢
│   ├── CameraDiagnostics.swift            i 診斷報告
│   ├── HUDFormatters.swift                AVCaptureDevice → 顯示文字
│   ├── AVCaptureVideoOrientation+Init.swift
│   └── Views/
│       ├── AspectMaskView.swift           預覽外殼 + 構圖框 + 三分線
│       ├── AudioMeterCardView.swift       音量計卡片
│       └── ToastView.swift                提示泡泡
├── Chat/
│   ├── ChatViewController.swift           UI 組裝 + 訊息列表
│   ├── ChatEngine.swift                   協定 + `KeywordChatEngine`
│   └── Views/PlannerCardView.swift        checklist / notes / action items 卡片
├── Media/
│   ├── MediaViewController.swift
│   └── MediaLibrary.swift                 儲存 + metadata + 4:3 裁切
├── Settings/
│   ├── SettingsViewController.swift
│   └── CameraSettingsStore.swift          UserDefaults persist + 變更通知
├── Planner/
│   └── ShotPlannerStore.swift             checklist / notes / action items / linked clip
├── Shared/
│   └── KeyboardObserver.swift             鍵盤升降監聽，可重用
└── Resources/                             Assets.xcassets / Info.plist / Base.lproj / .xcdatamodeld
scripts/
└── generate_app_icon.swift                用 CoreGraphics 產 1024×1024 AppIcon
```

## Documentation

每份檔案各自只做一件事，避免內容散落：

| 檔案 | 用途 |
|---|---|
| [`README.md`](./README.md) | 你正在看的這份。產品 / 架構速覽 |
| [`roadmap.md`](./roadmap.md) | Done + 還沒做的事（Short / Mid / Long Term + Technical Debt） |
| [`DECISIONS.md`](./DECISIONS.md) | 12 個架構決策的「為什麼」與放棄了什麼 |
| [`bugs.md`](./bugs.md) | 踩過的坑（症狀 / 根因 / 解法） |
| [`runbook.md`](./runbook.md) | Build、模擬器、icon 生成、清快取等實際指令 |
| [`docs/camera-architecture.md`](./docs/camera-architecture.md) | 相機頁 service 層、capture session、HUD 與資料流設計 |
| [`docs/development-workflow.md`](./docs/development-workflow.md) | 開發流程、build 驗證、真機測試、git 流程 |

## Build

模擬器：

```bash
xcodebuild -project CameraHuman.xcodeproj -scheme CameraHuman \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build
```

最低支援 iOS 13.0。`Info.plist` 內含 `NSCameraUsageDescription` / `NSMicrophoneUsageDescription` / `UILaunchStoryboardName`，啟動畫面已修，App 不再被 letterbox 在螢幕中央。

## Current Limitations

- `4:3` 目前是錄後裁切，仍需真機驗證不同方向與不同鏡頭的結果一致。
- 音訊監看是單一 capture connection 的 level meter，不是完整多軌 mixer。
- `Chat` 還是本地 keyword 引擎；架構已用 `ChatEngine` 協定預留 swap 點，但未接外部 AI。
- `Media` 是單層素材列表，沒有專案、資料夾或標籤系統。

