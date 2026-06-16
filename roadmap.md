# Roadmap

這份檔案是 `CameraHuman` 接下來打算做的事的**單一來源**。
任何「下一步要做什麼」「該重構什麼」「累積的技術債」都集中在這裡，避免散在 README 與 docs 三處 drift。

> 「Current Limitations」（已知做不到的事）放在 [`README.md`](./README.md)——那是現況描述，不是計畫。

## Short Term

按優先排序，越上面越該先做。

### 1. 真機驗證 4:3 + 前後鏡頭 + 錄影方向

模擬器看不到實機 capture 結果，是後續所有相機改動的前置。重點驗：

- 4:3 輸出裁切的 transform 在前鏡頭是否正確
- 實機 `IRIS` / `FPS` / `SHUTTER` / `ISO` 值是否合理（多數 iPhone `IRIS` 是 fixed，會顯示 `FIXED`）
- 橫直切換時 record button、lens stack、audio meter card 的位置是否對齊
- 前鏡頭 `4:3` 與 transform 是否同步

### 2. Quick Wins（每項 0.5~1 天，互不依賴，可穿插做）

架構紅利：service 層已拆乾淨，這批多數只要在 `CameraSession` 加 public API + VC 接手勢。

- **點擊對焦 / 曝光**：`CameraSession` 加 `focus(at:)` 包 `focusPointOfInterest` + `exposurePointOfInterest`，VC tap gesture 用 `captureDevicePointConverted` 轉座標。iOS 13 全支援。**需真機驗證**
- **捏合縮放**：`CameraSession` 加 `setZoom(factor:)` 包 `videoZoomFactor`（用 `ramp(toVideoZoomFactor:)` 平滑），切鏡頭時重置 factor。**需真機驗證**

### 3. 拍攝穩健性

- **錄影中斷處理**：已確認 `CameraSession` 完全沒監聽 `AVCaptureSession.wasInterruptedNotification` / `interruptionEndedNotification` / `runtimeErrorNotification`。來電、切後台、被搶 capture 時至少要把已錄段落安全落檔 + toast 告知。**需真機驗證**（模擬器無法模擬來電搶 session）
- **剩餘空間檢查**：`CameraRecorder` start 路徑檢查磁碟空間不足就擋；HUD 可加「可錄時間估計」chip

### 4. 把 Chat 接上真實 AI

[`ChatEngine`](./CameraHuman/Chat/ChatEngine.swift) 協定已預留 swap 點，目前實作 `KeywordChatEngine` 只是 keyword 比對。候選：

| 路徑 | 優點 | 缺點 |
|---|---|---|
| Apple Foundation Models（iOS 18.1+） | 裝置端、永久免費、不要 key、隱私好 | 需 iPhone 15 Pro / 16+，要拉 deployment target，模型較弱 |
| Gemini Flash 免費 tier | 中文強、免費額度高（~1500 RPD）、不綁卡 | 要 key、免費 tier 內容可能拿來訓練 |
| Claude Haiku | 一致性最佳、中文一流 | 需綁卡、超過 $5 credit 後計費 |

不論哪條：**API key 走 Settings 輸入 + Keychain，不寫死**。建議順序：先做 KeychainStore + Settings 的 key 輸入 UI（不綁供應商），再接其中一家。組 system prompt context 的材料（`MediaLibraryReading` / `CameraSettings` / `ShotPlanner` protocol）已現成。先用結構化 context + 「不確定就說不知道」的 instruction，能解 80% 場景。

## 待真機驗證（程式碼已完成，Phase 3）

> 這些已實作 + build + 單元測試過，但**模擬器沒相機 / 沒麥克風完全驗不了**，要拿 iPhone 跑才算完成。

- **手動控制（FPS / 曝光補償 EV / 手動曝光 ISO+快門 / 白平衡色溫）**：點 HUD chip 調整。FPS chip 點擊循環 24→30；ISO/SHUTTER 開「曝光面板」（AUTO 顯示 EV 滑桿 / MANUAL 顯示 ISO 段位 + 快門角度段位滑桿）；WB 開「白平衡面板」（AUTO / 色溫滑桿）。ISO 走 1/3 stop 段位（端點用鏡頭實際 min/max），快門走角度制（45°~360°，依 fps 換算速度，60Hz 防閃爍標 ⚡）。service API 在 `CameraSession`，純換算在 `CameraManualControls`，UI 在 `ManualControlSheetView`。
  - 已修：面板被 dock 切掉、FPS HUD 顯示 format 上限而非實際值。
  - 待驗：切鏡頭後手動值要不要重置；HD format 上限 30fps（60 要等 4K/高幀率 format）；曝光 ISO+快門互動實際成像。

## Mid Term

往「專業拍攝工具」走：

- **4K 畫質選項**：`CameraSettingsStore` quality 加 `UHD` → `.hd4K3840x2160` preset，不支援機型 fallback。注意 4:3 錄後裁切的輸出時間會變長。**需真機驗證**
- **AE/AF 鎖定**：長按預覽鎖定當前曝光 / 對焦點。手動控制已有，這是補互動。**需真機驗證**

其他：

- **HUD 狀態模型化**：chip 字串 array 換成型別化 struct，順手解 `IRIS=FIXED` 顯示策略（見 Technical Debt）。是後續 HUD 功能（可錄時間、警示色）的地基
- 擴充 `Media` 的素材**分類、搜尋、標籤**——目前單層列表
- `Chat` 與 `Media` 的 planner 連動從**單一 linked clip 升級為多素材 shot mapping**
- 把 `TopHUDView` / `BottomHUDView` 從 `CameraViewController` 拆出（VC 還有 ~700 行可再瘦，但前一輪 service 拆分後 ROI 已下降，不急）
- 補更多錄影成功 / 失敗狀態的細部提示

## Long Term

- 對焦控制：點擊對焦 + 手動對焦距離（曝光 / 白平衡的手動控制已做，見「待真機驗證」）
- 多軌音訊策略：不只 level meter，要能切換 input、可能多軌錄音
- 真正的 AI / 雲端 `Chat` 工作流：含 system prompt 注入 app 狀態 + tool calling（讓模型直接呼叫 `list_recordings()` / `get_settings()` 等）

## Known Technical Debt

不影響功能但會在改動時拖慢的東西：

- **4:3 是錄後裁切**，不是完整從 capture preset 到 framing pipeline 的一致設計。如果之後要做 RAW / proxy / 多格式輸出，這裡會變成 bottleneck。
- **`IRIS` 顯示策略**走 `device.lensAperture`，多數 iPhone 是 fixed → 顯示 `FIXED`；可改成 device-capability 導向，例如「不支援可變光圈時隱藏 IRIS chip 改顯示其他資訊」。
- **`CameraViewController` 還有 view 組裝邏輯 ~700 行**——可再抽 `TopHUDView` / `BottomHUDView`，但已經做過 service 拆分（`CameraSession` / `CameraRecorder` / `AudioLevelMonitor`）後 ROI 不大。
- **`AspectMaskView` 內部的 `aspectMaskTopHeightConstraint` / `aspectMaskBottomHeightConstraint` 目前都設 0**（讓預覽 full-bleed），結構保留但不發揮作用，看是要恢復裁切預覽顯示，還是直接移除這兩條 constraint。

## Done（最近完成的，避免 roadmap 看起來都不會做完）

> 完成後可以從上面的清單刪掉，但保留在這節短期內，方便回顧進度。完成超過幾個月就移除。

- ✅ 修啟動 letterbox（補 `UILaunchStoryboardName`）
- ✅ 重做底部 dock（32pt 自製 dock 取代預設 UITabBar）
- ✅ Camera HUD 找回光圈那組技術資訊（直立模式不再隱藏）
- ✅ 精簡 `i` 診斷資訊（18 行 → 5 行）
- ✅ Chat checklist 放大、加鍵盤避讓
- ✅ 升級 Xcode 16 同步資料夾、按職責分資料夾
- ✅ 拆分 `CameraViewController`（1264 → 697 行）：`CameraSession` / `CameraRecorder` / `AudioLevelMonitor` / `AspectMaskView` / `AudioMeterCardView` / `ToastView`
- ✅ 抽出 `ChatEngine` 協定、`KeyboardObserver`、`PlannerCardView`
- ✅ 鏡頭切換優化：點同鏡頭直接 noop、`AVCaptureVideoPreviewLayer` 只建一次、同 device 不重建 input、加 `isConfiguring` flag 避免重疊 configure 排隊
- ✅ 抽 `MediaLibraryReading` / `CameraSettings` / `ShotPlanner` protocol，`KeywordChatEngine` 改用 protocol 注入；補第一批 unit test（`KeywordChatEngineTests`，15 個 case 涵蓋所有 keyword 分支 / fallback / 4:3 vs 16:9 / spy 驗證）
- ✅ 補三組 unit test：`CameraDiagnosticsTests`（12）/ `ShotPlannerStoreTests`（14）/ `CameraSettingsStoreTests`（14），總計 **55 tests passing**。Store 的 init 加 `UserDefaults` 注入點讓測試用獨立 suite 隔離
- ✅ Media Quick Wins 三項（模擬器驗過）：列表縮圖 + 片長（抽 `MediaThumbnailProvider`，`AVAssetImageGenerator` 背景產圖 + NSCache）、長按 `UIContextMenuConfiguration`（Note / Link / Share / Save to Photos / Delete）、分享（`UIActivityViewController`）與匯出到照片（`PHPhotoLibrary`，補 `NSPhotoLibraryAddUsageDescription`）。swipe 操作保留
