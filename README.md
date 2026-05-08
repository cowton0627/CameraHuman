# CameraHuman

`CameraHuman` 是一個以 `UIKit + AVFoundation` 為主的 iOS 拍攝工具原型。現在的主軸不是單純相機 demo，而是把拍攝、音訊監看、素材管理、拍攝規劃整成同一個工作流。

## Current App Structure

底部 `Tab Bar` 目前分成四頁：

- `Camera`
  單一拍攝頁。整合相機預覽、錄影、鏡頭切換、音訊電平監看、格式資訊與技術 HUD。
- `Media`
  顯示已錄製素材，支援播放、刪除、素材註記，以及把某支素材 link 到拍攝 planner。
- `Chat`
  本地拍攝助理頁。可查看目前設定、最近素材、shot checklist、備忘與 action items。
- `Settings`
  管理拍攝偏好，例如錄影畫質、比例、啟動鏡頭與格線。

## Implemented Features

### Camera

- 使用 `AVCaptureSession` 同時接上 video input、audio input、`AVCaptureMovieFileOutput`
- 前後鏡頭切換
- 後鏡頭依實際硬體顯示可用鏡頭類型，不把 `portrait` 當成假鏡頭模式
- 上方拍攝 HUD
  - 格式，例如 `HD` / `FHD`
  - 比例，例如 `16:9` / `4:3`
  - 錄影時間與 `REC` 狀態
- 技術資訊 HUD
  - `LENS`
  - `FPS`
  - `SHUTTER`
  - `IRIS`
  - `ISO`
  - `WB`
- 底部錄影鍵
- 右下角音訊監看
  - 正常範圍：綠色
  - 接近上限：黃色
  - 爆音區：紅色
- 錄影完成後會顯示簡短 toast
- `16:9` / `4:3` 預覽構圖框與遮罩

### Media

- 錄影檔儲存到 app 的 `Documents/Recordings`
- 列表顯示建立時間與檔案大小
- 可播放 `.mov`
- 可刪除素材
- 可編輯素材註記
- 可把素材 link 到 planner

### Chat

- 顯示目前拍攝設定摘要
- 顯示最近素材摘要
- 內建 shot checklist
- 可編輯拍攝備忘
- 可保存 action items
- 顯示目前 link 的素材

### Settings

- `HD / FHD`
- `16:9 / 4:3`
- 預設前鏡頭 / 後鏡頭
- 顯示格線

## Important Files

- [`CameraHuman/CameraViewController.swift`](./CameraHuman/CameraViewController.swift)
  主拍攝頁與 `AVCaptureSession` 控制。
- [`CameraHuman/MediaLibrary.swift`](./CameraHuman/MediaLibrary.swift)
  素材儲存、列出、刪除、註記、`4:3` 輸出裁切。
- [`CameraHuman/MediaViewController.swift`](./CameraHuman/MediaViewController.swift)
  素材列表與播放器入口。
- [`CameraHuman/ChatViewController.swift`](./CameraHuman/ChatViewController.swift)
  拍攝助理與 planner UI。
- [`CameraHuman/ShotPlannerStore.swift`](./CameraHuman/ShotPlannerStore.swift)
  checklist、備忘、action items、linked clip 的本地儲存。
- [`CameraHuman/CameraSettingsStore.swift`](./CameraHuman/CameraSettingsStore.swift)
  拍攝設定的 `UserDefaults` 儲存與通知。
- [`CameraHuman/SettingsViewController.swift`](./CameraHuman/SettingsViewController.swift)
  設定頁 UI。
- [`CameraHuman/RootTabBarController.swift`](./CameraHuman/RootTabBarController.swift)
  app 的四個主要 tab 入口。

## Technical Docs

- [`docs/camera-architecture.md`](./docs/camera-architecture.md)
  相機頁的 capture session、鏡頭策略、錄影流程、HUD 與資料流設計。
- [`docs/development-workflow.md`](./docs/development-workflow.md)
  這個 repo 的實際開發、build 驗證、真機測試與 git 工作流程。

## Build Notes

目前 app 走 `SceneDelegate + RootTabBarController`，不再依賴 `Main.storyboard` 作為主要進入點。

本機若使用：

```bash
xcodebuild -scheme CameraHuman -project CameraHuman.xcodeproj -destination 'generic/platform=iOS' -derivedDataPath /tmp/CameraHumanDerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

目前已知阻塞不是 Swift 編譯錯誤，而是：

- `LaunchScreen.storyboard`
- `iOS 17.2 Platform Not Installed`

也就是說，現階段若 build 卡住，先檢查本機 Xcode / iOS platform 安裝狀態。

## Current Limitations

- `4:3` 目前是以預覽構圖框與輸出裁切為主，仍需真機再驗證不同方向與不同鏡頭的結果。
- 音訊監看目前是單一 capture session 的 level meter，不是完整多軌 mixer。
- `Chat` 目前是本地 planner / assistant，不是接外部 AI 或後端服務。
- `Media` 現在是單層素材列表，還沒有專案、資料夾或標籤系統。

## Next Recommended Work

- 移除或重做 `LaunchScreen.storyboard`，把本機 build 噪音先清掉
- 在真機上驗證前後鏡頭、`16:9 / 4:3`、錄影方向與裁切結果
- 擴充 `Media` 的素材分類與搜尋
- 把 `Chat` 的 planner 與素材管理做更深整合，例如 shot list 對應多支 clip
