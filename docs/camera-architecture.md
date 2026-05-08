# Camera Architecture

這份文件描述 `CameraHuman` 目前的相機頁技術設計，目的是讓後續開發時能先理解現有決策，再決定要不要重構，而不是直接把功能再堆回 [`CameraViewController.swift`](../CameraHuman/CameraViewController.swift)。

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

### 1. Camera View Controller

[`CameraViewController.swift`](../CameraHuman/CameraViewController.swift) 是目前單一拍攝頁的主控制器，負責：

- 建立與維護 `AVCaptureSession`
- 建立 `AVCaptureVideoPreviewLayer`
- 控制前後鏡頭切換
- 切換後鏡頭的實體 lens option
- 啟動 / 停止錄影
- 更新 HUD
- 更新音訊電平顯示
- 接收錄影完成 callback，並把檔案交給 `MediaLibrary`

### 2. Camera Settings Store

[`CameraSettingsStore.swift`](../CameraHuman/CameraSettingsStore.swift) 是拍攝設定的單一來源，使用 `UserDefaults` 保存：

- `VideoPreset`
- `AspectRatio`
- `StartupCamera`
- `showGrid`

設定變更後會送出 `.cameraSettingsDidChange`。

### 3. Media Library

[`MediaLibrary.swift`](../CameraHuman/MediaLibrary.swift) 處理錄影檔實際落地：

- 從暫存檔移入 `Documents/Recordings`
- 建立素材 metadata
- 列出素材
- 刪除素材
- 更新素材註記
- 在 `4:3` 模式下輸出裁切後的影片

### 4. Planner Store

[`ShotPlannerStore.swift`](../CameraHuman/ShotPlannerStore.swift) 雖然不是相機核心，但現在已經跟拍攝流程有連動：

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

目前 session 相關工作使用 `sessionQueue`，避免在主緒直接做昂貴的相機設定。

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

`LensMode` 目前只代表實體鏡頭類型，不代表拍攝風格：

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

### 開始錄影

使用者點底部錄影鍵後：

1. 檢查目前 `recordingState`
2. 若為 `idle`，進入 `startRecording()`
3. 建立暫存輸出 URL
4. 由 `AVCaptureMovieFileOutput` 開始錄影
5. `didStartRecordingTo` callback 後：
   - 狀態切到 `recording`
   - 啟動錄影 timer
   - 更新 HUD

### 停止錄影

1. 使用者再次點錄影鍵
2. 呼叫 `stopRecording()`
3. `didFinishRecordingTo` callback 後：
   - 停止 timer
   - 若成功，交由 `MediaLibrary.storeRecording(from:aspectRatio:)`
   - 若目前設定為 `4:3`，會先做輸出裁切
   - 存檔成功後顯示 toast

### 錄影狀態

目前使用 `RecordingState` 管控：

- `idle`
- `starting`
- `recording`
- `stopping`

這能避免使用者在開始 / 結束的過渡期重複點擊錄影鍵。

## Preview Aspect Strategy

目前 `16:9 / 4:3` 並不是只有改字樣，而是有兩層處理：

### 1. 預覽構圖層

相機預覽上有：

- `aspectMaskTopView`
- `aspectMaskBottomView`
- `aspectFrameView`
- `aspectFrameLabel`

這些元件提供：

- 上下遮罩
- 實際構圖框
- 當前比例標示

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

目前音訊監看使用 capture connection 的 `audioChannels` 讀取平均 power level，再轉成 0...1 的 normalized level。

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
3. `CameraViewController` 收到後更新：
   - guide visibility
   - aspect mask
   - capture session
   - lens options

若正在錄影中：

- 不會立刻整個重建 capture session
- 先顯示「部份設定會在結束目前錄影後套用」

### Camera -> Media

錄影完成後：

1. `CameraViewController`
2. `MediaLibrary.storeRecording(...)`
3. 儲存到 `Documents/Recordings`
4. 發送 `.mediaLibraryDidChange`
5. `MediaViewController` 刷新列表

### Media -> Chat

在 `Media` 頁可把某支素材 link 到 planner。

之後：

1. `ShotPlannerStore` 保存 `linkedRecordingName`
2. 發送 `.shotPlannerDidChange`
3. `ChatViewController` 更新 linked clip 顯示
4. `MediaViewController` 也同步刷新 subtitle

## Known Technical Debt

- `CameraViewController` 仍偏大，後續應拆出：
  - capture session coordinator
  - HUD view model
  - audio metering adapter
- `4:3` 目前是錄後裁切，不是完整從 capture preset 到 framing pipeline 的一致設計
- `IRIS` 現在仍是固定顯示，因為多數 iPhone 無實體可變光圈；若要更準確，可改成裝置能力導向的顯示策略
- `Chat` 與 `Media` 的 planner 連動目前是單一 linked clip，不是多素材 shot mapping

## Recommended Next Refactors

### Short Term

- 移除或重做 `LaunchScreen.storyboard`
- 真機驗證 `4:3` 裁切與前後鏡頭輸出方向
- 補更多錄影成功 / 失敗狀態提示

### Mid Term

- 把 capture session 管理從 view controller 拆出去
- 把 HUD 顯示值改成更清楚的狀態模型
- 讓 `Media` 支援專案、標籤或素材分類

### Long Term

- 加入更完整的手動控制
- 加入多軌音訊策略
- 規劃真正的 AI / 雲端 `Chat` 工作流
