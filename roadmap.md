# Roadmap

這份檔案是 `CameraHuman` 接下來打算做的事的**單一來源**。
任何「下一步要做什麼」「該重構什麼」「累積的技術債」都集中在這裡，避免散在 README 與 docs 三處 drift。

> 「Current Limitations」（已知做不到的事）放在 [`README.md`](./README.md)——那是現況描述，不是計畫。

## Short Term

按優先排序，越上面越該先做。

### 1. 真機驗證 4:3 + 前後鏡頭 + 錄影方向

模擬器看不到實機 capture 結果，重點驗：

- 4:3 輸出裁切的 transform 在前鏡頭是否正確
- 實機 `IRIS` / `FPS` / `SHUTTER` / `ISO` 值是否合理（多數 iPhone `IRIS` 是 fixed，會顯示 `FIXED`）
- 橫直切換時 record button、lens stack、audio meter card 的位置是否對齊
- 前鏡頭 `4:3` 與 transform 是否同步

### 2. 把 Chat 接上真實 AI

[`ChatEngine`](./CameraHuman/Chat/ChatEngine.swift) 協定已預留 swap 點，目前實作 `KeywordChatEngine` 只是 keyword 比對。候選：

| 路徑 | 優點 | 缺點 |
|---|---|---|
| Apple Foundation Models（iOS 18.1+） | 裝置端、永久免費、不要 key、隱私好 | 需 iPhone 15 Pro / 16+，要拉 deployment target，模型較弱 |
| Gemini Flash 免費 tier | 中文強、免費額度高（~1500 RPD）、不綁卡 | 要 key、免費 tier 內容可能拿來訓練 |
| Claude Haiku | 一致性最佳、中文一流 | 需綁卡、超過 $5 credit 後計費 |

不論哪條：**API key 走 Settings 輸入 + Keychain，不寫死**。先用結構化 context（把 camera 設定 / 最近錄影 / planner 狀態塞進 system prompt）+ 「不確定就說不知道」的 instruction，能解 80% 場景。

### 3. Media 滑動操作的 discoverability

目前 `Delete` / `Note` / `Link` 藏在 swipe 手勢，新使用者完全猜不到。候選：

- 長按 context menu（最少改動、最 iOS native）
- 標題列加 `Edit` 進入多選刪除模式
- 每 row 加 trash 圖示（最直接但視覺負擔重）

### 4. 補測試覆蓋率（順著已建的 test target）

第一批 `KeywordChatEngineTests` 已寫好。下一輪可補：

- `CameraDiagnosticsTests`：純函式，給 `Inputs` 驗輸出字串，~5 個 case
- `ShotPlannerStoreTests`：toggle / addActionItem 6 上限 / trim whitespace / persist→reload（需 ephemeral `UserDefaults` suite）
- `CameraSettingsStoreTests`：default 值 / persist→reload / 變更時 fire notification

跳過：VC、`CameraSession`、`CameraRecorder`、custom views（mock 成本太高，改靠手動 / 真機 / UI test）。

## Mid Term

- 擴充 `Media` 的素材**分類、搜尋、標籤**——目前單層列表
- `Chat` 與 `Media` 的 planner 連動從**單一 linked clip 升級為多素材 shot mapping**
- 把 `TopHUDView` / `BottomHUDView` 從 `CameraViewController` 拆出（VC 還有 ~700 行可再瘦，但前一輪 service 拆分後 ROI 已下降，不急）
- HUD 顯示值改成更清楚的**狀態模型**（目前是 chip 字串 array，無型別）
- 補更多錄影成功 / 失敗狀態的細部提示

## Long Term

- 更完整的手動控制：曝光、對焦、白平衡
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
