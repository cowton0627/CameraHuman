# Runbook

這份檔案紀錄這個 repo 的**操作流程**：build、跑模擬器、拍截圖、生 icon、清快取、git。
跟 `development-workflow.md` 不同的地方：那份講「怎麼工作 / 思考順序」，這份講「直接複製貼上的指令」。

> 這個 repo **沒有 Firebase / 後端 / 部署管線**，所以那些章節留白。如果未來接了任何雲端服務（例如接 AI 走 Gemini），再回來補對應段落。

---

## Build

### 模擬器 build（最常用，一定先跑這個確認沒打壞）

```bash
xcodebuild -project CameraHuman.xcodeproj -scheme CameraHuman \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Debug build
```

只看錯誤 / 警告：

```bash
xcodebuild ... build 2>&1 | grep -E "error:|warning:|BUILD" | head -20
```

完整 log 想留下來：

```bash
xcodebuild ... build > /tmp/camerahuman-build.log 2>&1
rg -n "error:|warning:" /tmp/camerahuman-build.log
```

### 實機 build（CODE_SIGN 開啟）

```bash
xcodebuild -project CameraHuman.xcodeproj -scheme CameraHuman \
  -destination 'generic/platform=iOS' build
```

### Release build

```bash
xcodebuild -project CameraHuman.xcodeproj -scheme CameraHuman \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -configuration Release build
```

---

## 跑測試

Tests 放在 [`CameraHumanTests/`](./CameraHumanTests/)，需要先在 Xcode UI 加 **Unit Testing Bundle** target（File → New → Target → iOS / Test / Unit Testing Bundle）。

加完 target 後：

```bash
xcodebuild -project CameraHuman.xcodeproj -scheme CameraHuman \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  test
```

或 Xcode 內按 `Cmd+U`。

只跑指定一個 test class：

```bash
xcodebuild -project CameraHuman.xcodeproj -scheme CameraHuman \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -only-testing:CameraHumanTests/KeywordChatEngineTests test
```

只看結果 / 不要 build log：

```bash
xcodebuild ... test 2>&1 | grep -E "Test Case|Test Suite|passed|failed"
```

---

## 模擬器流程

### 列出可用模擬器

```bash
xcrun simctl list devices available | grep -E "iPhone 1[5-9]"
```

### 啟動模擬器（若已關機）

```bash
SIM_UDID="E1AEB518-A302-4363-A03F-DBCB5E81B7EC"   # 換成你的 iPhone 15 Pro 或別台 UDID
xcrun simctl boot "$SIM_UDID" 2>&1 | head -1
xcrun simctl bootstatus "$SIM_UDID" -b               # 等 boot 完
open -a Simulator                                    # 把模擬器視窗叫出來
```

### 安裝、啟動、拍截圖

```bash
APP_PATH="$HOME/Library/Developer/Xcode/DerivedData/CameraHuman-bvoczkonslqumicoaxavjrjkxpmp/Build/Products/Debug-iphonesimulator/CameraHuman.app"

xcrun simctl install "$SIM_UDID" "$APP_PATH"
xcrun simctl terminate "$SIM_UDID" individualStudio.CameraHuman 2>&1 | head -1   # 確保乾淨
xcrun simctl launch "$SIM_UDID" individualStudio.CameraHuman
sleep 3
xcrun simctl io "$SIM_UDID" screenshot /tmp/camerahuman.png
```

### 給模擬器麥克風 / 相機權限

```bash
xcrun simctl privacy "$SIM_UDID" grant camera individualStudio.CameraHuman
xcrun simctl privacy "$SIM_UDID" grant microphone individualStudio.CameraHuman
```

### 關閉硬體鍵盤連接（要驗證軟鍵盤 / 鍵盤避讓時必做）

```bash
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
xcrun simctl shutdown "$SIM_UDID"
xcrun simctl boot "$SIM_UDID"
```

### 看模擬器 console log

```bash
xcrun simctl spawn "$SIM_UDID" log stream --level=debug \
  --predicate 'subsystem == "individualStudio.CameraHuman"'
```

---

## 重生 App Icon

icon 是 [`scripts/generate_app_icon.swift`](./scripts/generate_app_icon.swift) 用 CoreGraphics 畫的 1024×1024 PNG。改顏色 / 形狀就改 script 裡的常數重跑：

```bash
swift scripts/generate_app_icon.swift
file CameraHuman/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
```

預期輸出：`PNG image data, 1024 x 1024, 8-bit/color RGBA, non-interlaced`

---

## 清快取

### DerivedData（最常需要清的）

```bash
rm -rf ~/Library/Developer/Xcode/DerivedData/CameraHuman-*
```

清完下次 build 會重編全部，比較慢但能解很多奇怪的 build 卡住問題。

### 模擬器內容

```bash
xcrun simctl erase all                 # 全部模擬器恢復原廠
xcrun simctl erase "$SIM_UDID"         # 單一模擬器
```

### Xcode 個人狀態（一般不用清，除非 IDE 行為怪異）

```bash
rm -rf CameraHuman.xcodeproj/xcuserdata
```

`xcuserdata/` 已在 `.gitignore` 內，不會影響 git。

---

## Git workflow

### 開工前

```bash
git status --short
git pull --ff-only
```

### Commit 前檢查

```bash
git status --short                     # 有沒有漏掉的新檔
git diff --stat                        # 改動範圍
git diff --cached                      # 已 staged 的內容
```

### 不要 commit 的東西（已被 .gitignore 涵蓋）

- `.env` / API key / credentials
- `xcuserdata/`、`*.xcuserstate`
- `DerivedData/`
- `.DS_Store`

### 常見 git 操作

```bash
# 把已被追蹤的檔案改成不追蹤（保留本地）
git rm --cached <path>

# 看單一檔案歷史
git log --oneline --follow CameraHuman/Camera/CameraViewController.swift

# 撤銷 staged 的檔
git restore --staged <path>

# 撤銷 working tree 改動（會弄丟改動，謹慎）
git restore <path>
```

### Push

```bash
git push origin main
```

不要 force push 到 main。

---

## 觀察重點

### 哪些檔案改動該特別小心

- `CameraHuman.xcodeproj/project.pbxproj`：升過 `objectVersion = 71` + 同步資料夾。手動編輯易壞，盡量讓 Xcode 自動處理
- `Resources/Info.plist`：權限描述、`UILaunchStoryboardName`、orientation 都靠這個檔
- `.gitignore`：新增類別（例如改用 SPM、加 fastlane）時要回來看一下
- `scripts/generate_app_icon.swift`：改完一定要把 `AppIcon-1024.png` 重跑一次再 commit，不要單 commit script 不 commit png

### Build 失敗先分型

- **Code 問題**：Swift 編譯錯、symbol unresolved、type mismatch → 真的 regression，要修
- **環境問題**：iOS Platform Not Installed、simulator service 不見 → 環境問題，不是程式錯
- **SourceKit 雜訊**：「No such module 'UIKit'」之類，build 仍 succeeded → 忽略，重啟 Xcode 即可

詳見 `bugs.md` 第 8 條。
