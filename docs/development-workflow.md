# Development Workflow

這份文件描述 `CameraHuman` 目前建議的開發流程。重點不是理論上的最佳實務，而是這個 repo 目前真的需要怎麼做，才能避免反覆踩同樣的坑。

## Goals

這份流程主要處理四件事：

- 改功能時不要再把 UI、session、設定流弄亂
- 分清楚 code regression 跟本機 Xcode 環境問題
- 把真機驗證重點固定下來
- 讓 git 狀態保持可追蹤

## Project Reality

目前這個專案有幾個現實條件：

- 主 app 是 `UIKit`
- 相機與錄影核心依賴 `AVFoundation`
- 主入口是 `SceneDelegate + RootTabBarController`（自製 dock，不是 `UITabBar` 預設外觀）
- `Camera` 是目前主要功能頁，已拆成 `CameraSession` / `CameraRecorder` / `AudioLevelMonitor` 三個 service + 多個 custom view
- `Media / Chat / Settings` 已經接進同一個拍攝工作流
- `project.pbxproj` 採用 Xcode 16 同步資料夾，加新檔到對應子資料夾即自動納入 build，不必手動編輯 pbxproj

## Core Workflow

每次開發建議照這個順序走。

### 1. Start With Scope

先明確定義這次改動是以下哪一類：

- `Camera`
- `Media`
- `Chat`
- `Settings`
- `Build / wiring`

如果是相機功能，先看：

- [`CameraViewController.swift`](../CameraHuman/Camera/CameraViewController.swift) — view + callback wiring
- [`CameraSession.swift`](../CameraHuman/Camera/CameraSession.swift) — capture session、鏡頭、權限
- [`CameraRecorder.swift`](../CameraHuman/Camera/CameraRecorder.swift) — 錄影狀態機
- [`CameraSettingsStore.swift`](../CameraHuman/Settings/CameraSettingsStore.swift)
- [`MediaLibrary.swift`](../CameraHuman/Media/MediaLibrary.swift)

如果是 app 導航或啟動問題，另外看：

- [`RootTabBarController.swift`](../CameraHuman/App/RootTabBarController.swift)
- [`SceneDelegate.swift`](../CameraHuman/App/SceneDelegate.swift)
- [`Info.plist`](../CameraHuman/Resources/Info.plist)

### 2. Check Git Before Editing

先確認 worktree，不要在髒狀態下失去判斷力。

```bash
git status --short
```

要看幾件事：

- 有沒有未追蹤的新檔
- 有沒有你這次不打算碰的舊改動
- `project.pbxproj` 或 `Info.plist` 有沒有被一起改到

如果 worktree 本來就不乾淨，之後回報時要把自己的改動和既有改動分開講。

### 3. Read Before Editing

不要直接進檔案硬改。先理解目前狀態模型。

相機功能至少要先搞清楚：

- 目前 camera position 是什麼
- 有哪些 discovered lens options
- session 在哪裡建立與重建
- 錄影輸出在哪裡開始與結束
- HUD 的數值是即時計算還是寫死
- 比例變更是只影響 UI，還是真的進輸出流程

這一步的目的很直接：避免改到一個按鈕，結果 session、preview、HUD 同時壞掉。

### 4. Implement the Smallest Correct Change

修改時優先遵守這些原則：

- 不要把假的硬體能力呈現在 UI 上
- 不要把 `portrait` 當成鏡頭
- 前鏡頭若沒有多焦段差異，就只顯示單一 front mode
- 後鏡頭鏡頭列表應該由 runtime capability 決定
- 錄影與音訊監看盡量維持在單一 capture workflow 內

如果是 UI 調整，也不要只看視覺；要一起檢查：

- 觸控區域是否合理
- 小螢幕是否擠壓
- 錄影中狀態是否可讀
- 音訊顏色是否仍然符合語意

### 5. Build Verification

改完後，先跑固定 build 指令，不要每次換花樣。模擬器 build：

```bash
xcodebuild -project CameraHuman.xcodeproj -scheme CameraHuman \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build > /tmp/camerahuman-build.log 2>&1
```

再查 log：

```bash
rg -n "error:|warning:" /tmp/camerahuman-build.log
```

### 6. Interpret Build Correctly

看到 build fail 時，不要立刻說功能壞了。先分型。

#### Code issue

這類算真正 regression：

- Swift compile error
- unresolved symbol
- type mismatch
- missing file wiring
- duplicated method / property

#### Environment issue

這類要明確說是本機環境問題，不要誤判成程式錯：

- `iOS Platform Not Installed`（缺對應 SDK）
- simulator service / platform runtime 缺失
- `xcrun simctl` 找不到指定 device UDID

`LaunchScreen.storyboard` 之前因為沒在 `Info.plist` 註冊 `UILaunchStoryboardName` 會被 letterbox，這個已在當前版本修正。

## Real Device Verification

這個 app 很多功能不能只靠 build。以下是每次相機功能大改後應該實機檢查的項目。

### Camera Startup

- App 啟動後是否直接進 `Camera`
- 預設前鏡頭 / 後鏡頭是否符合 `Settings`
- 權限未給時 UI 是否仍可理解

### Lens Behavior

- 後鏡頭鏡頭按鈕是否只顯示實際存在的鏡頭
- 前鏡頭是否沒有出現假的多焦段模式
- 切到前鏡頭後，lens UI 是否正確重建
- 預覽畫面是否真的切到對應 input

### Recording Flow

- 錄影鍵點下去是否立刻切到錄影狀態
- `REC` 與 timer 是否有更新
- 再點一次是否正常停止
- 錄影完成是否有 toast
- 錄出的檔是否進入 `Media`

### Aspect Ratio

- `16:9` 構圖框是否合理
- `4:3` 構圖框是否合理
- `4:3` 輸出檔在 `Media` 播放時是否比例正確
- 前鏡頭 `4:3` 是否有方向或 transform 問題

### Audio Monitoring

- 安靜環境下是否接近低值
- 一般說話是否主要落在綠色
- 較大聲時是否進黃色
- 爆音風險時是否進紅色
- 軌道數顯示是否合理

### Planner / Media Sync

- `Media` link 一支 clip 後，`Chat` 是否同步顯示
- 刪掉 linked clip 後，planner 是否自動清空 link
- 素材註記修改後，列表是否立即刷新

## Camera-Specific Guardrails

這些是目前專案已經踩過坑的地方，之後不要再退回去。

### 1. Do Not Fake Lens Modes

- 不要把 `portrait` 當 lens
- 不要為前鏡頭硬做 `0.5x / 1x / 3x`
- 不要用型號猜測硬體，優先用 runtime discovery

### 2. Do Not Read UIKit State Off Main Thread

以下這些值要在 main thread 讀：

- `view.window`
- `windowScene`
- `interfaceOrientation`

否則很容易再出現 `Main Thread Checker`。

### 3. Do Not Hide Real State Changes Behind Labels

如果 HUD 顯示某個值：

- 它應該反映真實狀態
- 不應只是裝飾字串

特別是：

- `LENS`
- `REC`
- 音訊顏色
- 比例標示

## Git Hygiene

每次收尾前至少檢查一次：

```bash
git status --short
```

關注點：

- 新檔有沒有漏加
- 是否誤改 `project.pbxproj`
- 是否留下暫時測試碼
- 是否多出不該存在的 debug label / print

如果工作內容很大，建議把 commit 切成：

1. `feature / architecture`
2. `UI polish`
3. `docs`

不要把所有邏輯、UI、文件、資源都塞進單一不清楚的 commit。

## Documentation Workflow

這個 repo 現在建議維持三層文件：

### 1. README

用途：

- 給第一次進 repo 的人快速了解產品方向與現況

位置：

- [`README.md`](../README.md)

### 2. Architecture Notes

用途：

- 解釋技術設計與重要決策

位置：

- [`docs/camera-architecture.md`](./camera-architecture.md)

### 3. Development Workflow

用途：

- 規範實際開發、驗證與交付流程

位置：

- 這份文件

## Suggested Working Loop

如果沒有特殊情況，最實際的日常循環是：

1. `git status --short`
2. 讀相關檔案
3. 做最小正確修改
4. 跑 `xcodebuild`
5. 看 build log
6. 若是相機功能，做真機驗證
7. 更新必要文件
8. 再看一次 `git status --short`

## Roadmap

下一步要做什麼集中在 [`../roadmap.md`](../roadmap.md)。這份文件只描述「怎麼工作」，不再列待辦項。

需要新加 next-step 項目時，**寫到 `roadmap.md`，不要寫到這裡**。
