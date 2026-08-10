# Bugs / 踩過的坑

這份檔案紀錄做這個 repo 過程中**實際踩過的坑**：症狀、根因、解法。
目的不是炫耀，而是讓未來再看到類似徵兆時能立刻聯想到「這之前處理過了」。

格式：每條附 **症狀**（看到什麼）/ **根因**（真正的原因）/ **解法**（怎麼修）。

---

## 1. 啟動畫面被 letterbox（上下黑邊、tab 沒貼底）

**症狀**：App 啟動後畫面被夾在螢幕中間，上下出現黑色 letterbox 區。tab dock 雖然在「畫面底」但實際螢幕底是黑的。

**根因**：`Info.plist` 沒登記 `UILaunchStoryboardName`。iOS 找不到 launch storyboard 就用 legacy compatibility mode，把整個 window 當成老 App 跑，所以強制 letterbox。**這是 App 啟動配置問題，不是 view hierarchy / safeArea 問題**——一開始誤判方向，花了時間找錯地方。

**解法**：在 `Info.plist` 加：
```xml
<key>UILaunchStoryboardName</key>
<string>LaunchScreen</string>
```
完全刪除模擬器上的 App 再重裝（iOS 會 cache launch image），重 build 後黑邊消失。

**之後辨識**：「上下都有黑邊 + UI 元件莫名沒貼到螢幕邊」第一個查 `Info.plist` 的 launch storyboard key。

---

## 2. dock 修好 letterbox 後又看起來「過大」

**症狀**：解掉 letterbox 後 dock 變成貼底的，但使用者覺得「太誇張大」、按鈕擠成一團、視覺上很多空白。

**根因**：dock view 高度 44pt 且 pin 到 `view.bottomAnchor`。iPhone home indicator 占 34pt，所以 dock view 內 safeArea bottom 上方只剩 10pt。stackView 的 bottom 又 pin 到 dock 的 `safeAreaLayoutGuide.bottom`，等於按鈕擠在 dock 最頂端 10pt，剩下 34pt 是空白 blur 蓋在 home indicator 上。視覺比例失調 = 「看起來大但內容卻擠」。

**解法**：定義 `dockContentSize: CGFloat = 32`，dock view 的 top pin 到 `view.safeAreaLayoutGuide.bottomAnchor - 32`，bottom 仍 pin 到 `view.bottom`。這樣按鈕區固定 32pt 在 home indicator 上方，blur 自然延伸蓋住 home indicator。

**之後辨識**：當 view pin 到 `view.bottom` 又用內部 safeArea 排內容時，要算清楚「safeArea inset 是否 > view 高度」。

---

## 3. CameraVC 兩處 `-44` magic number 散落

**症狀**：dock 從 44pt 改成 32pt 後，相機頁的 record button 跟其他 HUD 元件位置全錯——記得一處改但找不到第二處。

**根因**：[`CameraViewController`](./CameraHuman/Camera/CameraViewController.swift) 的 portrait 跟 landscape 兩組 layout constraint 都寫死 `-44` 來避開 dock：
```swift
bottomHUDView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -44)  // portrait
bottomHUDView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -44)  // landscape
```
沒有 single source of truth，dock 改大小其他畫面會連動壞。

**解法**：兩處 `-44` 都改 `view.safeAreaLayoutGuide.bottomAnchor` / `safeAreaLayoutGuide.trailingAnchor`。`RootTabBarController` 透過 `additionalSafeAreaInsets` 把 dock 高度餵進去，HUD 自動避開，不再依賴 magic number。

**之後辨識**：`grep -n "constant: -[0-9]\+" CameraHuman/` 看有沒有寫死偏移。

---

## 4. Chat 鍵盤點開不會收下、輸入欄不避讓

**症狀**：點 Chat 輸入欄鍵盤跳出來但沒地方按收回；輸入欄被鍵盤蓋住看不到正在打字。

**根因**：
- 沒有 `tapGesture` + `view.endEditing()` 的點空白收鍵盤
- 沒有 `tableView.keyboardDismissMode = .interactive` 的下拉收鍵盤
- 輸入欄 bottom pin 到 `view.safeAreaLayoutGuide.bottomAnchor`，但 safeAreaLayoutGuide **不會跟著鍵盤動**，要自己用 `keyboardWillChangeFrameNotification` 監聽 + 改 constraint constant

**解法**：抽出 [`KeyboardObserver`](./CameraHuman/Shared/KeyboardObserver.swift) 包裝鍵盤通知，VC 設一個 closure 處理 constraint constant 與 layout 動畫。同時加 tap gesture（`cancelsTouchesInView = false`）+ `tableView.keyboardDismissMode = .interactive` + `textFieldShouldReturn` 內 `resignFirstResponder()`。

**之後辨識**：「鍵盤蓋住輸入欄」第一個查有沒有在用 `keyboardLayoutGuide` 或 `keyboardWillChangeFrameNotification`。

---

## 5. Chat checklist 三項擠成一團

**症狀**：Chat planner 卡片內 checklist 三個項目高度只有 32pt 各，加上下面 notes / save / linked clip / action items 全部被夾在 300pt 內，整張卡密集到難用。

**根因**：[`ChatViewController`](./CameraHuman/Chat/ChatViewController.swift) 對 plannerStackView 加了 `heightAnchor.constraint(lessThanOrEqualToConstant: 300)`，把卡片硬限制在 300pt 內，內容又一堆只能擠扁。

**解法**：移除 300pt 上限讓卡片依內容自然伸展；checklist 按鈕高度 32pt → 44pt（符合 Apple HIG 觸控區建議），字級 12pt → 14pt，corner radius 9 → 10。

**之後辨識**：當 stackView 內容被擠扁時，先 `grep "heightAnchor.constraint" + "lessThanOrEqualToConstant"` 找有沒有上限被誤設。

---

## 6. `xcrun simctl io ... screenshot` 報 `Timeout waiting for screen surfaces`

**症狀**：模擬器跑一段時間後再呼叫 screenshot，回傳：
```
Unable to lookup in current state: Shutdown
Timeout waiting for screen surfaces
```

**根因**：模擬器被 idle shutdown，或前一個 `xcrun simctl terminate` 順帶把整個 sim 關掉。`simctl io` 拍不了已關閉的 sim。

**解法**：每次 launch 前先：
```bash
xcrun simctl boot <UDID> 2>&1 | head -1   # 已 boot 會回 "Booted already"
xcrun simctl bootstatus <UDID> -b          # 等 boot 完成
xcrun simctl install <UDID> "$APP_PATH"
xcrun simctl launch <UDID> <bundle-id>
```

**之後辨識**：拍不到圖時先確認 `xcrun simctl list devices | grep Booted` 是否有目標 sim。

---

## 7. 模擬器軟鍵盤永遠不出現

**症狀**：iOS 模擬器點 `UITextField`，鍵盤完全沒出現（first responder 確實是文字欄、`viewDidAppear` 內 `becomeFirstResponder` 也呼叫了，但畫面沒鍵盤）。

**根因**：macOS 模擬器預設 `ConnectHardwareKeyboard = true`，把 Mac 的鍵盤直接接進模擬器；iOS 認為已有實體鍵盤，就不顯示軟鍵盤。

**解法**：
```bash
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
xcrun simctl shutdown <UDID>
xcrun simctl boot <UDID>
```
或在 Simulator 視窗：`I/O > Keyboard > Connect Hardware Keyboard` 取消勾選。

**之後辨識**：要驗證鍵盤行為（避讓、收下、樣式）一律先關 hardware keyboard。

---

## 8. SourceKit 一直報 `No such module 'UIKit'`

**症狀**：`<new-diagnostics>` 反覆出現：
```
CameraViewController.swift:6:8 ✘ No such module 'UIKit' (SourceKit)
```
但 `xcodebuild` 完整 build 仍 `BUILD SUCCEEDED`。

**根因**：SourceKit indexer 在 pbxproj 結構大改後（升 synced folders、移檔到子資料夾、新增 Camera/AVCaptureVideoOrientation+Init.swift 等）一時跟不上，誤把檔案當成獨立 macOS source 而非 iOS target 的一部分。`UIKit` 是 iOS-only 模組，所以對 macOS 上下文找不到。

**解法**：忽略。等 SourceKit 自己 reindex 或重啟 Xcode 即可。**判斷準則：build 成功 = 真的編得過**，SourceKit 是 IDE 端的索引狀態，不一定即時同步。

**之後辨識**：看到只 SourceKit 報錯但 `xcodebuild` build succeeded 時，不需要任何修正。

---

## 9. Xcode 個人 breakpoint 檔被追進 git

**症狀**：`git status` 一直冒出：
```
modified: CameraHuman.xcodeproj/xcuserdata/<user>.xcuserdatad/xcdebugger/Breakpoints_v2.xcbkptlist
```
每次 Xcode 開檔點 breakpoint 都會 dirty。

**根因**：repo 從來沒有 `.gitignore`，所以 Xcode 個人狀態（`xcuserdata/`、`*.xcuserstate`）都被當成正常檔案追蹤。

**解法**：
1. 建立 `.gitignore` 涵蓋：`xcuserdata/`、`DerivedData/`、`build/`、`.DS_Store`、`.swiftpm/`、`Package.resolved`、`Pods/`、`.idea/`、`.vscode/` 等
2. 對已追蹤的 `Breakpoints_v2.xcbkptlist`：`git rm --cached <path>`（保留本地，但從 git 中拿掉）
3. commit

**之後辨識**：`git ls-files | grep xcuserdata` 看是否還有殘留追蹤；新 repo 首次 init 時要先建 `.gitignore` 再開始 commit。

---

## 10. 鏡頭點 1x 卡住 0.3~1 秒

**症狀**：進 Camera 後預設已是 1x，但手動再點一次 1x 按鈕時畫面會卡 0.3~1 秒，preview 短暫黑屏 / 停格，看起來像當機。

**根因**：三層浪費疊加：
1. `lensButtonTapped` 完全不檢查「點到的鏡頭跟當前鏡頭是否相同」，永遠觸發 `session.configure(...)`
2. `CameraSession.configure` 不論是不是同 device，都會跑完整 `beginConfiguration` / 移除舊 input / 建新 input / 移除舊 audio / 建新 audio / `commitConfiguration` 一輪
3. `session.onConfigured` callback 每次都 `AVCaptureVideoPreviewLayer(session: …)` 創新 layer——雖然 `attachPreviewLayer` 內 guard 擋掉只裝一次，但這個新 layer 在 init 時會自動把自己掛上 session 的 connection，session 短暫多了一條無用 connection，再被 ARC 釋放

實機上每次 begin/commit 就 0.3~1 秒，期間 preview 直接黑。視覺上 = 卡。

**解法**：
- VC `lensButtonTapped`：先比 `device.uniqueID`，相同直接 return
- VC `viewDidLoad`：preview layer 改成只建一次掛上去，`onConfigured` 不再每次重建（layer 綁到 session，session 加減 input 它自動跟著刷新）
- `CameraSession.configure`：
  - 同 device 不動 video input
  - 同 audio device 不動 audio input
  - `sessionPreset` 已是目標時不重設
  - 加 `isConfiguring` flag 避免使用者狂點時，多個 configure 任務在 sessionQueue 排隊
  - 失敗路徑記得 `commitConfiguration`，不留懸空 begin

**之後辨識**：UI 操作後 preview 短暫黑屏，先看是不是觸發了不必要的 capture session 重新 configure；對「重複觸發 noop 路徑」一律加短路。

## 11. Visual regression 在 CI 永遠紅、本機永遠綠

**症狀**：`iOS Tests` workflow 的 UI Tests job 持續失敗，只掛在 `test_stableScreensMatchBaselines` 的 `assistant` 這一頁（1.17% / 1.22%，門檻 0.5%），其餘 5 個 UI smoke test 全過；同一個測試在本機跑是綠的。

**根因**：文字抗鋸齒的次像素差異。baseline 錄在本機、比對跑在 GitHub runner，即使模擬器與 Xcode 版本完全相同（`iPhone 17 / iOS 26.4.1` + Xcode 26.4.1），字的邊緣灰階過渡仍有落差。逐像素比對把這種細邊當成差異，文字越多累積越高——`assistant` 文字量最大所以先破線。

**排除過的假設**（都不是）：UI 改了忘記更新 baseline（baseline 之後 App 原始碼零改動）、模擬器規格不同（一致）、隨機 flake（兩次 1.17% / 1.22% 穩定）、版面位移（平移 ±8px 比對，`dy=0` 就是最佳解）。

**解法**：比對改為「成塊差異」——差異遮罩做一次 5×5 形態學侵蝕，只留整個鄰域都超標的像素。細節與參數見 `DECISIONS.md` §15。**已在 CI 驗收**（commit `5982b35`，Unit + UI 兩個 job 皆 success），此問題結案。

**之後辨識**：像素級 visual regression 只要 baseline 與比對環境不同機，就會有這種「本機綠、CI 紅、數字穩定不隨機」的特徵。看到就往算繪差異想，不要先懷疑 UI；判斷方法是把 CI artifact 的實際截圖抓下來，看差異是**細線**（算繪雜訊）還是**色塊**（真的回歸）。

**驗證紀律**：改完比對演算法後，要拿「刻意注入的回歸」當對照組跑一次——把 baseline 的一顆按鈕塗掉，確認測試真的會紅（實測 0.617%，與離線試算的 0.61% 相符）。否則計數寫錯導致永遠算出 0 時，測試會「通過」而變成擺設。

## 12. UI test 在 CI 偶發逾時（`waitForExistence` 5 秒不夠）

**症狀**：修好 §11 之後，只改了兩個 `.md` 檔的 commit `a336d89` 仍然讓 UI Tests job 紅掉。失敗點是 `waitForExistence(timeout: 5)` 逾時（點 Settings 後標題沒出現），**不是**像素比對。

**判讀方式**：看失敗的行號。§11 是掛在 `assertSnapshot` 的 `XCTAssertLessThanOrEqual`（訊息含 `Visual difference for ...`）；這次是掛在測試主體的 `XCTAssertTrue`。另外因為 `continueAfterFailure = false`，測試能跑到後面的 settings 區段，反而證明前面 assistant 的像素比對**已經通過**——§11 的修復是有效的。

**根因**：GitHub runner 效能浮動很大。同一份程式碼，`VisualRegressionTests` 本機跑 18–22 秒、CI 上一次 22 秒、這次 **47.9 秒**，慢了一倍多。原本 2–5 秒的等待上限在快的時候夠用，慢的時候就爆掉。這個脆弱點一直都在，只是以前每次都先死在像素比對，沒機會浮現。

**解法**：把 18 處硬編碼的 timeout 統一成 `UITestTimeout.standard`（15 秒，定義在 `CameraHumanUITests/UITestTimeout.swift`）。等待上限放寬不影響正常速度——`waitForExistence` 一看到元素就返回，上限只決定「真的卡住時多久判定失敗」。本機實測放寬前後耗時相同（5–22 秒），6/6 通過。

**已在 CI 驗收**（commit `4b9da35`，Unit + UI 兩個 job 皆 success），此問題結案。而且這次是在**比失敗那次更差的條件**下通過的——`VisualRegressionTests` 在 runner 上跑了 **70.9 秒**（失敗那次是 47.9 秒），等待上限放寬後照樣過。runner 耗時實測分布：

| 執行 | `VisualRegressionTests` 耗時 | 結果 |
|---|---|---|
| 本機 | 17.4 秒 | ✅ |
| CI `5982b35` | 22 秒 | ✅ |
| CI `a336d89` | 47.9 秒 | ❌ 5 秒上限逾時 |
| CI `4b9da35` | 70.9 秒 | ✅ 15 秒上限 |

**之後辨識**：CI 紅但本機綠、而且**同一份程式碼在 CI 上的耗時差異很大**時，先懷疑等待上限，不要急著改被測程式。UI test 的 timeout 不要散落成 magic number，集中成一個常數才好一次調整。從上表也看得出來，CI 耗時可以是本機的 4 倍且沒有上限保證——之後若再遇到偶發逾時，優先考慮再調高這個常數，而不是加 sleep 或重試。
