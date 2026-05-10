# Camera Architecture

這份文件描述 `CameraHuman` 目前的相機頁技術設計，目的是讓後續開發時能先理解現有決策，再決定要不要重構，而不是直接把功能再堆回 [`CameraViewController.swift`](../CameraHuman/Camera/CameraViewController.swift)。

## Scope

目前這份設計文件只涵蓋：

- `Camera` tab 的拍攝頁
- 錄影流程
- 鏡頭切換策略
- 預覽比例遮罩
- 音訊監看
- 與 `Media` / `Settings` 的資料流

不涵蓋：

- `Media` 列表細節
- `Chat` planner UI 細節
- 未來若要加入的相片拍攝、手動曝光、外接麥克風細部控制

## Primary Components

相機頁的職責已經從單一 `CameraViewController` 拆成「VC 只負責 view 與 callback wiring，所有 AV 互動由獨立 service 持有」的結構。

### 1. Camera Service Layer

- [`CameraSession.swift`](../CameraHuman/Camera/CameraSession.swift)
  持有 `AVCaptureSession`、`AVCaptureMovieFileOutput`、`sessionQueue`，負責：
  - 相機 / 麥克風權限請求
  - 鏡頭枚舉（`availableLensOptions`）與當前選擇
  - 前後鏡頭切換
  - capture session 設定與 commit
  - 提供 `audioMeterConnection` 給 metering
  - callback：`onConfigured(device, lensTitle)` / `onConfigureFailed(message)` / `onLensesChanged()`
- [`CameraRecorder.swift`](../CameraHuman/Camera/CameraRecorder.swift)
  錄影狀態機 + `AVCaptureFileOutputRecordingDelegate`，負責：
  - 狀態機：`idle / starting / recording / stopping`
  - 計時 timer
  - 接 `MediaLibrary.storeRecording` 把成品落地
  - callback：`onStateChange` / `onTimerTick` / `onStartedFile` / `onSaved` / `onFailed`
- [`AudioLevelMonitor.swift`](../CameraHuman/Camera/AudioLevelMonitor.swift)
  Timer 輪詢 `AVCaptureConnection` 的 audio channels，把 power level 正規化成 0~1 + track count 回 callback。

### 2. Camera View Controller

[`CameraViewController.swift`](../CameraHuman/Camera/CameraViewController.swift) 只負責：

- view hierarchy 組裝（top HUD / bottom HUD / preview / 自訂 view）
- 把上面三個 service 的 callback 接到 UI 更新
- HUD chip 文字渲染與 layout 切換（portrait / landscape）
- Lens 按鈕點擊轉發到 `CameraSession`、錄影鍵點擊轉發到 `CameraRecorder`

VC **不**直接持有任何 `AVCaptureSession` / `AVCaptureMovieFileOutput` / `AVCaptureDevice` 物件，所有 AV state 都從 service 走。

### 3. Camera Custom Views

- [`AspectMaskView.swift`](../CameraHuman/Camera/Views/AspectMaskView.swift)
  預覽外殼。內含 vignette、aspect mask、構圖框 + 標籤、三分線。掛 `AVCaptureVideoPreviewLayer`。
- [`AudioMeterCardView.swift`](../CameraHuman/Camera/Views/AudioMeterCardView.swift)
  音量計卡片：MIC 標籤 + TRACKS + dB + 4 條動態 bar。`update(level:trackCount:audioAuthorized:)` 一次餵完，內部處理顏色分級。
- [`ToastView.swift`](../CameraHuman/Camera/Views/ToastView.swift)
  自動淡入 / 等 1.6s / 淡出的提示泡泡。

### 4. Camera Settings Store

[`CameraSettingsStore.swift`](../CameraHuman/Settings/CameraSettingsStore.swift) 是拍攝設定的單一來源，使用 `UserDefaults` 保存：

- `VideoPreset`
- `AspectRatio`
- `StartupCamera`
- `showGrid`

設定變更後會送出 `.cameraSettingsDidChange`。

### 5. Media Library

[`MediaLibrary.swift`](../CameraHuman/Media/MediaLibrary.swift) 處理錄影檔實際落地：

- 從暫存檔移入 `Documents/Recordings`
- 建立素材 metadata
- 列出素材
- 刪除素材
- 更新素材註記
- 在 `4:3` 模式下輸出裁切後的影片

### 6. Planner Store

[`ShotPlannerStore.swift`](../CameraHuman/Planner/ShotPlannerStore.swift) 雖然不是相機核心，但現在已經跟拍攝流程有連動：

- 保存 shot checklist
- 保存拍攝備忘
- 保存 action items
- 保存目前 linked clip

## Capture Session Design

目前相機頁使用單一 `AVCaptureSession`，而不是把畫面、收音、錄影拆成多套 session。

### Session 內的主要元件

- `AVCaptureDeviceInput`
  - video input
  - audio input
- `AVCaptureMovieFileOutput`
  - 實際錄影輸出
- `AVCaptureAudioDataOutput`
  - 提供音訊 meter 讀值
- `AVCaptureVideoPreviewLayer`
  - 顯示即時預覽

### 為什麼目前採單一 session

- 架構較簡單，適合現在這個原型階段
- 相機預覽、錄影、音訊監看可共用同一個 capture pipeline
- 可避免不同 session 之間的同步問題

### 目前的限制

- 音訊監看不是完整 mixer，只是從 capture connection / audio channel 讀 level
- 沒有獨立多軌概念
- 沒有真正的 pro-level monitoring routing

## Threading Model

`sessionQueue` 由 `CameraSession` 持有（`com.camerahuman.capture-session`），所有改動 capture session 的工作都跑在這條 queue 上。`CameraRecorder` 透過 `session.queue.async` 共用同一條 queue 做 start/stop recording，避免兩個 service 各自維護 queue 造成同步問題。

### 原則

- UI 更新在 main thread
- `AVCaptureSession` 設定與切換在 `sessionQueue`

### 已修正的問題

先前曾在背景 queue 讀 `view.window` / `windowScene` / `interfaceOrientation`，觸發 `Main Thread Checker`。

現在的原則是：

- 先在 main thread 取得 `interfaceOrientation`
- 再把這個值傳進背景 queue 使用

這條規則之後不能退回去，否則同樣會再出現主緒警告。

## Lens Model

### 現在的鏡頭模型

`CameraSession.LensMode` 目前只代表實體鏡頭類型，不代表拍攝風格：

- `ultraWide`
- `wide`
- `telephoto`

### 為什麼不把 portrait 當 lens

`portrait` 不是實體鏡頭，而是拍攝模式 / 處理效果。之前若把它當 lens，會導致：

- UI 上看起來像鏡頭切換
- 實際上卻沒有對應硬體變化
- 前鏡頭尤其容易出現「按了有模式名，但畫面沒變」的假切換

所以目前設計明確規定：

- 只列出實際存在的 `AVCaptureDevice.DeviceType`
- 不把 `portrait` 放進 lens selector

### 前後鏡頭的呈現策略

後鏡頭：

- 依裝置實際可用的 `.builtInUltraWideCamera`
- `.builtInWideAngleCamera`
- `.builtInTelephotoCamera`

前鏡頭：

- 如果只有單一前鏡頭，就只顯示單一 front option
- 不硬做假的 `0.5x / 1x / 3x`

這個策略是為了避免在像 iPhone 13 這類裝置上，前鏡頭 UI 看似有不同模式，實際畫面卻沒有變化。

## Recording Flow

錄影狀態機與 file output delegate 都在 `CameraRecorder` 內部，VC 只透過 callback 收事件。

### 開始錄影

1. 使用者點錄影鍵 → VC 呼叫 `recorder.start(interfaceOrientation:)`
2. `CameraRecorder` 檢查當前 state 是否為 `idle`、session 有相機權限、`movieOutput` 沒在錄
3. state 切到 `starting`，`onStateChange` 回 callback 給 VC 更新按鈕外觀
4. 在 `session.queue` 上建立暫存輸出 URL，呼叫 `movieOutput.startRecording(to:recordingDelegate:)`
5. delegate 的 `didStartRecordingTo` 回到 main thread 後：
   - state 切到 `recording`，`onStateChange` 觸發 UI
   - 啟動 1Hz `onTimerTick` callback 給 VC 更新 HUD timer
   - `onStartedFile(URL)` 給 VC 顯示「錄影中：檔名」

### 停止錄影

1. 使用者再次點錄影鍵 → VC 呼叫 `recorder.stop()`
2. state 切到 `stopping`、`onStateChange` 觸發 UI
3. delegate 的 `didFinishRecordingTo` 回到 main thread 後：
   - 停 timer，state 回 `idle`
   - 成功：在背景 queue 呼叫 `MediaLibrary.storeRecording(from:aspectRatio:)`，4:3 模式會在這裡做輸出裁切；完成後 `onSaved(MediaRecording)` 觸發 toast
   - 失敗：`onFailed(message)` 給 VC 顯示

### 錄影狀態

`CameraRecorder.State` 列舉：

- `idle`
- `starting`
- `recording`
- `stopping`

`starting` / `stopping` 過渡期間，VC 把錄影鍵 disabled，避免重複點擊。

## Preview Aspect Strategy

目前 `16:9 / 4:3` 並不是只有改字樣，而是有兩層處理：

### 1. 預覽構圖層

`AspectMaskView` 內部包：

- vignette
- aspect mask top / bottom
- 構圖框
- 比例標籤
- 三分線（rule of thirds）

VC 透過 `previewView.setAspectRatio(_:)` / `previewView.setGuidesVisible(_:)` 切換顯示，不再直接動內部 subviews。

### 2. 輸出裁切層

當設定為 `4:3` 時，`MediaLibrary` 會在錄影完成後使用 `AVMutableVideoComposition` 做輸出裁切。

也就是說：

- `16:9` 走原始輸出
- `4:3` 走錄後裁切

### 目前風險

`4:3` 的裁切已接上，但仍需要真機驗證：

- 前鏡頭方向
- 後鏡頭方向
- 不同裝置 transform 是否一致

這是目前最該實機驗證的區塊之一。

## HUD Design

### Top HUD

上方 HUD 分成兩層：

1. primary status strip
   - `FORMAT`
   - `FRAME`
   - `TIME / REC`
2. technical info grid
   - `LENS`
   - `FPS`
   - `SHUTTER`
   - `IRIS`
   - `ISO`
   - `WB`

技術資訊目前做成兩排三欄，而不是一排塞滿，原因很直接：

- 一排六格在手機上太擠
- 數值難讀
- 錄影中會讓 HUD 失去快速掃視的作用

### Bottom HUD

底部目前分三區：

- 左側操作
  - 切換前後鏡頭
  - 檢視資訊
- 中間錄影鍵
- 右側音訊卡片

這樣做是為了避免錄影鍵與音訊卡片互相擠壓。

## Audio Meter Strategy

`AudioLevelMonitor` 用 0.12s timer 輪詢 `AVCaptureConnection` 的 `audioChannels`，取最大平均 power level，轉成 0~1 normalized level + track count，回 callback 給 VC。VC 再把值轉發給 `AudioMeterCardView.update(level:trackCount:audioAuthorized:)`，由 view 內部處理顏色分級與 bar 高度動畫。

### 顏色規則

- 正常範圍：綠色
- 接近上限：黃色
- 過熱區：紅色

這比單色 meter 更符合一般錄音 / 相機介面的習慣，因為使用者會直接把紅色理解成 clipping risk。

### 現況

目前顯示的是簡化監看：

- 一個 compact audio card
- 軌道數
- 簡化 bar meter
- level 百分比

不是完整 waveform，也不是多軌細節檢視。

## Data Flow

### Settings -> Camera

`SettingsViewController` 改變設定後：

1. `CameraSettingsStore` persist 到 `UserDefaults`
2. 發送 `.cameraSettingsDidChange`
3. `CameraViewController` 收到後：
   - 透過 `AspectMaskView` 更新 guide visibility 與 aspect 框
   - 若 recorder 為 `idle`，呼叫 `session.resetPositionFromSettings()` + `session.configure(...)` 重建 session
   - 若正在錄影，先顯示「部份設定會在結束目前錄影後套用」，不打斷當前錄影

### Camera -> Media

錄影完成後：

1. `CameraRecorder.didFinishRecordingTo` delegate
2. 在 background queue 呼叫 `MediaLibrary.storeRecording(...)`
3. 儲存到 `Documents/Recordings`，4:3 模式做輸出裁切
4. 發送 `.mediaLibraryDidChange`
5. `MediaViewController` 刷新列表
6. `CameraRecorder.onSaved` 回 main thread 給 VC 顯示 toast

### Media -> Chat

在 `Media` 頁可把某支素材 link 到 planner。

之後：

1. `ShotPlannerStore` 保存 `linkedRecordingName`
2. 發送 `.shotPlannerDidChange`
3. `ChatViewController` 更新 linked clip 顯示
4. `MediaViewController` 也同步刷新 subtitle

## Known Technical Debt

- `4:3` 目前是錄後裁切，不是完整從 capture preset 到 framing pipeline 的一致設計
- `IRIS` 顯示走 `device.lensAperture`，多數 iPhone 是 fixed 因此會顯示 `FIXED`；若要更準確可改成裝置能力導向的顯示策略
- `Chat` 與 `Media` 的 planner 連動目前是單一 linked clip，不是多素材 shot mapping
- `CameraViewController` 仍有 ~700 行的 view 組裝與 chip 渲染邏輯；可再抽 `TopHUDView` / `BottomHUDView` / 把 chip 渲染抽成獨立 helper，但價值低於前面已做的 service 拆分

## Recommended Next Refactors

### Short Term

- 真機驗證 `4:3` 裁切與前後鏡頭輸出方向
- 補更多錄影成功 / 失敗狀態提示
- 把 `Chat` 接上真實 AI（已有 `ChatEngine` 協定可換實作）

### Mid Term

- 把 HUD 顯示值改成更清楚的狀態模型
- 讓 `Media` 支援專案、標籤或素材分類
- 把 `TopHUDView` / `BottomHUDView` 拆出，VC 再瘦一輪

### Long Term

- 加入更完整的手動控制
- 加入多軌音訊策略
- 規劃真正的 AI / 雲端 `Chat` 工作流（含 system prompt 注入 app 狀態 + tool calling）
