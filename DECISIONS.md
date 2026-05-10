# Architecture Decisions

這份檔案記錄 `CameraHuman` 在演進過程中做過的關鍵設計決定。
每條都附**為什麼這樣選**，以及**放棄了什麼方案**——這樣未來重新檢視時，能判斷該決定是否仍然成立。

> README 講「現在長什麼樣」，DECISIONS 講「為什麼是這個樣」。

---

## 1. 自製 dock，不用預設 `UITabBar`

**做法**：[`RootTabBarController`](./CameraHuman/App/RootTabBarController.swift) 把 `tabBar.isHidden = true`，自己畫一條 32pt 高的 blur dock，貼在 `safeAreaLayoutGuide.bottom` 上方。

**為什麼**：
- 攝影 App 主畫面要儘量留給預覽，預設 `UITabBar` 49pt 太佔空間
- 自製可以控制顏色、icon 大小、blur 風格、選中狀態，不被 system 樣式綁住
- 自製可以隨時做進一步互動（如錄影中隱藏、長按手勢等）

**放棄**：保留 `UITabBar` 改顏色——能改的 API 太少，做不到想要的視覺密度。

---

## 2. dock 內容區固定 32pt

**為什麼**：
- Apple 官方 49pt 對攝影 App 太厚
- 量過字級 + icon SF Symbol 18pt，32pt 已足夠避開誤觸
- 32pt + home indicator（~34pt）= 視覺總高度 ~66pt，比 49pt + 34pt = 83pt 省一截

**放棄**：40pt（舒適但仍嫌厚）、24pt（按起來會誤觸隔壁）。

---

## 3. dock 的 blur 延伸到螢幕底（蓋住 home indicator）

**做法**：dockView pin 到 `view.bottom`，但內部 stackView pin 到 `safeAreaLayoutGuide`，按鈕只佔上半 32pt，下半是純 blur 過渡到 home indicator。

**為什麼**：blur 延伸到螢幕邊緣才不會在 home indicator 區出現一條突兀的純黑帶。

**放棄**：dockView pin 到 `safeAreaLayoutGuide.bottom`——home indicator 區會變純黑，視覺斷裂。

---

## 4. 服務層拆分：`CameraSession` / `CameraRecorder` / `AudioLevelMonitor`

**做法**：[`CameraViewController`](./CameraHuman/Camera/CameraViewController.swift) 不直接持有 `AVCaptureSession`。所有 AV 互動透過：
- [`CameraSession`](./CameraHuman/Camera/CameraSession.swift) — capture session、鏡頭、權限
- [`CameraRecorder`](./CameraHuman/Camera/CameraRecorder.swift) — 錄影狀態機 + delegate
- [`AudioLevelMonitor`](./CameraHuman/Camera/AudioLevelMonitor.swift) — 音量輪詢

**為什麼**：
- 重構前 VC 1264 行做 9 件事，動任何一個按鈕都要先理解錄影 + 音訊 + lens 切換 + HUD 渲染全套
- 拆完 VC → 697 行（-45%），每個 service 各自可以獨立測試
- 未來如果要把 capture 換成 AVCaptureMultiCamSession 或加新功能，只動對應 service

**放棄**：保持 monolithic VC（簡單但繼續長下去會無法維護）；改用 MVVM ViewModel（額外抽象層、UIKit 沒有 binding 機制硬接會更糟）。

---

## 5. 升級 pbxproj 到 Xcode 16 同步資料夾（`objectVersion = 71+` / `PBXFileSystemSynchronizedRootGroup`）

**為什麼**：
- 砍完死碼後檔案分散到 7 個子資料夾，傳統 pbxproj 每個檔要手動註冊（PBXFileReference + PBXBuildFile + PBXGroup + PBXSourcesBuildPhase 四處），改一檔要動 4 處 UUID
- 同步資料夾 = 「這個資料夾下所有 .swift 自動進 Sources phase、所有 .xcassets 進 Resources phase」，新增/搬檔都不用動 pbxproj
- 唯一例外是 `Info.plist`（`INFOPLIST_FILE` build setting 直接指向它），用 `PBXFileSystemSynchronizedBuildFileExceptionSet` 排除

**放棄**：保留 `objectVersion = 56` + 手動註冊每個新檔——拆 11 個新檔等於 44 處 UUID 編輯，太脆弱。

---

## 6. `ChatEngine` 協定預留 swap 點，**先不接** AI

**做法**：[`Chat/ChatEngine.swift`](./CameraHuman/Chat/ChatEngine.swift) 定義 `ChatEngine` protocol，預設實作 `KeywordChatEngine`（純本地 keyword 比對）。

**為什麼**：
- 接 AI 要做的事不只是 API call：API key 安全儲存、結構化 context、串流回應、錯誤處理、選供應商，每件都會拖慢核心拍攝功能的進度
- 留協定就好，未來換成 `GeminiChatEngine` / `ClaudeChatEngine` / `AppleFoundationModelChatEngine` 一行注入就完事
- 目前 `KeywordChatEngine` 至少能回答 `目前設定` / `最近素材` / `下一步建議` 三類常見問題，不算白做

**放棄**：直接寫死接某家 API（綁死供應商，未來換成本上升）；走 RAG（個人 repo 沒有累積 corpus，過度工程）。

---

## 7. 後鏡頭按硬體實際能力列鏡頭，前鏡頭只給單一 mode

**做法**：[`CameraSession.refreshLenses`](./CameraHuman/Camera/CameraSession.swift) 用 `AVCaptureDevice.default(_:for:position:)` 探測 `.builtInUltraWideCamera` / `.builtInWideAngleCamera` / `.builtInTelephotoCamera`，沒有的就不顯示。

**為什麼**：
- iPhone 13 / SE 等機型沒有望遠鏡頭，UI 顯示 `3x` 但按了沒反應就是 bug
- 前鏡頭從來只有單一鏡頭，硬列 `0.5x / 1x / 3x` 是欺騙

**放棄**：寫死三顆鏡頭按鈕（在不支援的機型上會看似可用實則無效）；把 `portrait` 當 lens mode（`portrait` 是處理效果，不是實體鏡頭，會混淆「按了畫面有變嗎」的判斷）。

---

## 8. 單一 `AVCaptureSession` 同時處理預覽 / 錄影 / 音量

**為什麼**：
- 原型階段架構越單純越好
- 多 session 之間要做時鐘同步、connection 路由，工程量大
- 目前需求（同時看 preview + meter + 錄製）單 session 完全能做

**放棄**：拆成 preview session + recording session + audio session——pro-level 監看會需要，但現在還沒到。

**權衡**：未來如果要加 RAW 或多軌音訊，這個決定可能要重看。

---

## 9. `sessionQueue` 由 `CameraSession` 持有，不是 VC

**為什麼**：
- 所有 AV 設定要在背景 queue 跑，避免主緒卡
- queue 放在 service 內部 + 透過 service callback 回 main thread，VC 完全不需要知道 queue 存在
- `CameraRecorder` 透過 `session.queue.async` 共用同一條 queue 做 start/stop，避免兩條 queue 同步問題

**放棄**：每個 service 各自一條 queue（同步成本）；queue 在 VC（VC 跟 AVFoundation 又耦合回去）。

---

## 10. `4:3` 走錄後裁切（在 `MediaLibrary.storeRecording`），不改整條 capture pipeline

**做法**：錄影一律以 16:9 native 寫入暫存，存進 `Documents/Recordings` 時若設定為 4:3 就用 `AVMutableVideoComposition` 重新輸出裁切版本。

**為什麼**：
- 改 capture preset / format 會影響 preview 比例、錄影同步、orientation transform，每改一個東西都要重驗
- 錄後裁切只在儲存路徑做事，不影響即時 capture
- 預覽端用 `AspectMaskView` 顯示 4:3 框讓使用者構圖，實際輸出是錄完後再切

**放棄**：完整 pipeline 走 4:3 capture——技術正確但工程量大，目前 ROI 不夠。

**權衡**：如果未來要做 RAW 或 ProRes，這個決定會變成 bottleneck，需要重新設計。

---

## 11. AppIcon 用 CoreGraphics script 生成，不外包設計

**做法**：[`scripts/generate_app_icon.swift`](./scripts/generate_app_icon.swift) 用 `CGContext` + `CGGradient` 畫 1024×1024 PNG，輸出到 `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`。

**為什麼**：
- 個人 repo、原型階段，不需要找設計師
- 改色 / 改造型只要改 script 重跑，比 Figma export 還快
- 確定品牌方向後再升級到專業設計，初期不必要

**放棄**：用 SF Symbol 直接當 icon（iOS 圓角會把 symbol 切到，需要自己處理 padding）；找線上免費 icon（授權麻煩）。

---

## 12. 補 `UILaunchStoryboardName` 修 letterbox，而非移除 LaunchScreen

**做法**：在 [`Resources/Info.plist`](./CameraHuman/Resources/Info.plist) 加 `UILaunchStoryboardName = LaunchScreen`。

**為什麼**：
- App 啟動時如果沒登記 launch storyboard，iOS 會把整個視窗 letterbox 在中間（上下黑邊）當作老 App 跑——這是症狀，不是 layout 問題
- 加一個 plist key 解掉，比改 view hierarchy 來得正確
- `Base.lproj/LaunchScreen.storyboard` 已經存在，補 key 即可，不必重做

**放棄**：刪掉 storyboard 改用純 SwiftUI launch screen（要改更多東西）；忽略黑邊（不是真的修，使用者持續看到）。
