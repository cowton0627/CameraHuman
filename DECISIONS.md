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

## 11. AppIcon 改用「光圈＋影人」品牌圖，PNG 是目前 source of truth

**做法**：以 image generation 產生 1024×1024 的不透明 PNG，直接存放在 [`AppIcon.appiconset/AppIcon-1024.png`](./CameraHuman/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png)。主圖形以光圈包住抽象人物，紅橘色圓點代表錄影，深色底與銀色鏡片對應專業攝影工具。iOS 會套用圓角遮罩，因此原圖維持滿版正方形，不自行畫圓角。

**為什麼**：
- 舊版日落圓盤容易被理解成天氣或風景 App，沒有清楚表達 CameraHuman 的「拍攝＋人物創作」定位
- 單一高對比符號縮到 Home Screen 尺寸後仍可辨識，比多物件或寫實相機圖案更適合 App icon
- 暖色錄影點保留明確的攝影語意，深色技術感也更接近 App 內的專業拍攝介面

**規格與驗證**：1024×1024 PNG、無 alpha、無文字、無外框；2026-08-07 已確認資產規格。專案 build 當時因本機缺少 iOS 26.4 Platform，停在 `LaunchScreen.storyboard`，不是 icon 資產錯誤。

**取代的舊方案**：[`scripts/generate_app_icon.swift`](./scripts/generate_app_icon.swift) 仍保留作為舊版 CoreGraphics 圖示的歷史參考，但不再是目前 icon 的生成來源；不要重跑後覆蓋現行 PNG。

**放棄**：延用日落圖（產品語意不明）；用 SF Symbol 或一般相機外框（辨識度偏通用）；加入文字（小尺寸不可讀）。

---

## 12. 補 `UILaunchStoryboardName` 修 letterbox，而非移除 LaunchScreen

**做法**：在 [`Resources/Info.plist`](./CameraHuman/Resources/Info.plist) 加 `UILaunchStoryboardName = LaunchScreen`。

**為什麼**：
- App 啟動時如果沒登記 launch storyboard，iOS 會把整個視窗 letterbox 在中間（上下黑邊）當作老 App 跑——這是症狀，不是 layout 問題
- 加一個 plist key 解掉，比改 view hierarchy 來得正確
- `Base.lproj/LaunchScreen.storyboard` 已經存在，補 key 即可，不必重做

**放棄**：刪掉 storyboard 改用純 SwiftUI launch screen（要改更多東西）；忽略黑邊（不是真的修，使用者持續看到）。

---

## 13. 手動控制：service API + 純邏輯分層，UI 用「混用」互動

**做法**：手動控制（FPS / 曝光補償 / 手動曝光 ISO+快門 / 白平衡色溫）切三層：
- [`CameraManualControls`](./CameraHuman/Camera/CameraManualControls.swift) — 純換算 / clamp / 滑桿映射，**不依賴 `AVCaptureDevice`**，可單元測試
- [`CameraSession`](./CameraHuman/Camera/CameraSession.swift) — `setFrameRate` / `setExposureBias` / `setManualExposure` / `setWhiteBalance` 等 public API，全走 `sessionQueue` + `lockForConfiguration`；`manualCapabilities()` 回傳能力與當前值快照給 UI
- [`ManualControlSheetView`](./CameraHuman/Camera/Views/ManualControlSheetView.swift) — 資料驅動的底部面板，不知道相機細節，純接 callback

**UI 互動採「混用」**：
- **離散值（FPS）**：點 chip 直接循環 24→30→60，不開面板——三檔而已，循環最快
- **連續值（ISO / 快門 / EV / 色溫）**：點 chip 從底部彈滑桿面板——值域連續，非滑桿不可

**為什麼**：
- 把可測的換算邏輯抽離 device 互動，是這個 repo 既有的分層慣例（如 `HUDFormatters` / `CameraDiagnostics`），手動控制沿用
- AV 設定一律走 service + sessionQueue，VC 不碰 `AVCaptureDevice`（DECISIONS #4 的延伸）
- 曝光面板用 AUTO/MANUAL segmented：AUTO 下是「自動曝光 + EV 補償」，MANUAL 下是「custom ISO+快門」，兩者互斥，用模式切換比塞一堆滑桿清楚

**放棄**：全部 chip 都用面板（FPS 三檔用面板多一次點擊，不划算）；常駐一排控制（佔預覽空間，四項全擺更擠）；點 chip 循環連續值（ISO 上百個值點不完，不可行）。

---

## 14. ISO / 快門用「段位」而非連續滑桿；快門走「角度制」

**背景**：初版 ISO / 快門是連續無段滑桿。真機試用發現不專業——中間一堆無意義的值，慢速快門區還佔掉大半行程。攝影慣例是離散段位（stops）。

**做法**（純邏輯在 [`CameraManualControls`](./CameraHuman/Camera/CameraManualControls.swift)，滑桿吸附在 `ManualControlSheetView`）：
- **ISO**：1/3 stop 標準段位（100/125/160/200/250/320/400…），**端點用鏡頭實際 `minISO` / `maxISO`**（iPhone minISO 常是 34 之類非標準值，保留它才用得到最低光），中間鋪標準 stop。滑桿吸附到最近段位。
- **快門：角度制**（跟 BlackMagic 一致），不是直接列速度。段位 = 快門角度 [45°, 90°, 172.8°, 180°, 270°, 360°]，依當前 fps 即時換算速度顯示（180° @ 24fps = 1/48）。180° 是電影感甜蜜點。
- **60Hz 防閃爍標示**：速度 ≈ 1/60 或 1/120 時在面板標 `⚡`（台灣電網 60Hz，日光燈下選這些避橫紋）。

**為什麼角度制**：快門角度是電影機的本質單位——同一角度在不同 fps 下動態模糊感一致（180° 永遠是「半圈曝光」）。直接列速度的話，換 fps 就要換一整套數字；用角度則 fps 一變、速度自動跟著換算。BlackMagic 列的 1/48·1/50·1/96·1/100 其實就是常用角度 + 防閃爍值的換算結果。

**放棄**：連續滑桿（無段、不專業）；直接列快門速度段位（換 fps 要重編清單，且失去「角度」這個跨 fps 一致的語意）；ISO 從 100 寫死起跳（用不到鏡頭的低 ISO）。

## 15. Visual regression 比對「成塊差異」而非逐像素，才能跨機器成立

**背景**：`VisualRegressionTests` 在 CI 上長期紅燈（`assistant` 這一頁差 1.17% / 1.22%，門檻 0.5%），本機卻是綠的。查證過程排除了所有明顯嫌疑：

- **不是 UI 改了忘記更新 baseline**：baseline 錄於 2026-08-07 16:56，之後 App 原始碼一個檔案都沒動過（只有測試檔本身被改）
- **不是模擬器規格不同**：CI 與 baseline 都是 `iPhone 17 / iOS 26.4.1` + Xcode 26.4.1
- **不是 flake**：兩次跑分別是 1.17% 和 1.22%，穩定超標一倍多
- **不是版面位移**：把 CI 截圖上下平移 ±8px 逐一比對，`dy=0` 就是最佳解，偏一格差異立刻從 1.29% 跳到 3.88%

把 CI artifact 裡的 `actual-assistant` 截圖抓下來逐像素分析，答案是**文字抗鋸齒**：差異像素有 59.7% 落在字的輪廓上，分布是一條條 30–40px 高的水平帶（正好是每行文字的高度），筆畫核心兩邊一致、只有邊緣那圈灰階過渡不同。同一台機器算繪一致，換一台就有次像素層級的落差。

**為什麼只有 `assistant` 紅**：它文字量最大（整段說明 + 三顆快捷按鈕 + 對話），累積的邊緣差異最多；`media-empty` 和 `settings` 文字少，同樣的雜訊被稀釋到門檻以下。所以另外兩頁不是「沒問題」，只是還沒踩到線。

**做法**（[`VisualRegressionTests.swift`](./CameraHumanUITests/VisualRegressionTests.swift)）：算出逐像素差異遮罩後，**做一次形態學侵蝕**——只有整個 5×5 鄰域都超標的像素才計入。抗鋸齒是沿著筆畫的 1–2px 細邊，侵蝕後消失；元件位移或消失是成塊的區域，侵蝕後幾乎不受影響。

用真實資料調出來的參數（`channelTolerance = 12`、`clusterRadius = 2`、門檻 `0.002`）：

| 情境 | 原本逐像素 | 侵蝕後 |
|---|---|---|
| CI vs baseline（抗鋸齒雜訊，兩次獨立取樣） | 1.22% / 1.17% ❌ | **0.034% / 0.023%** ✅ |
| 版面整體位移 6px | 9.45% | **1.76%** ❌ |
| 一顆按鈕消失（80×340） | 0.66% | **0.61%** ❌ |

雜訊被壓掉約 36 倍，真實回歸幾乎無損。門檻 0.002 對實測最大雜訊 0.034% 有約 6 倍餘裕。

**為什麼不選另外三條路**：
- **放寬門檻到 2%**：最省事，但等於讓「一顆按鈕消失」（0.66%）也過關——把測試廢掉了
- **baseline 改在 CI 錄**：能根治，但每次更新 baseline 都要從 artifact 撈圖，維護成本高，且本機就再也驗不了
- **CI 跳過這個測試**：CI 綠了但覆蓋率是假的，而 CI 正是最需要它把關的地方

**已知限制**（刻意接受）：侵蝕會讓**小於約 80×80px 的改動**落到門檻以下（實測 30×120px 的改動只有 0.095%，抓不到）；**低於 channel tolerance 的全域色偏**也抓不到（例如整體藍色 +12%，在深色 UI 上多數像素的差值不到 12）。這個測試的定位是「大範圍版面回歸」，細節回歸靠 5 個 UI smoke test 和人眼。

**踩過的坑**：先試過「先降取樣再比對」（4×4 / 8×8 / 16×16 區塊平均），失敗——區塊平均會把雜訊也一起放大，「缺按鈕」（0.66%）反而比抗鋸齒雜訊（1.3–2.0%）還小，完全分不開。也試過用整張圖的平均差當第二道關卡，同樣無效（雜訊 1.363 vs 色偏 2.356，只差 1.7 倍，而「缺按鈕」0.402 比雜訊還低）。**關鍵不在差異的「量」，而在差異的「形狀」**——雜訊是細線，回歸是色塊。
