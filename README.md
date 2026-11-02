# FlexDisplay

類 [BetterDisplay](https://github.com/waydabber/BetterDisplay) 嘅 **macOS 選單列**螢幕工具（MVP v1.1）。

Menu-bar utility for macOS 14+：列舉螢幕、切換解像度／刷新率、軟件（伽瑪）亮度、常用預設、軟熄屏、**實驗性虛擬螢幕**。

> **唔係** BetterDisplay 替代品。DDC/CI、EDID、XDR、PIP 等見下方 Roadmap。

---

## 點樣喺 Mac 打開／執行（How to run）

### 方法 A — XcodeGen（建議）

1. 將成個 `FlexDisplay/` 資料夾複製去 Mac（或解壓 `FlexDisplay.tar.gz`）。
2. 安裝 [Xcode 15+](https://developer.apple.com/xcode/) 同 XcodeGen：`brew install xcodegen`
3. 喺專案根目錄執行：
   ```bash
   ./scripts/generate-xcodeproj.sh
   open FlexDisplay.xcodeproj
   ```
4. **Signing & Capabilities** → 揀 **Team**；保持 **App Sandbox OFF**。
5. Run（⌘R）→ 選單列 `display` 圖示。

### 方法 B — 冇 XcodeGen

見 v1 README 步驟：新建 macOS App，拖入 `Sources/FlexDisplay/*.swift` 同 `Resources/`，自訂 Info.plist（`LSUIElement`）、entitlements（sandbox false）。

### 方法 C — SwiftPM（僅編譯檢查）

```bash
swift build
```

---

## 已實作（What works）

| 功能 | 說明 |
|------|------|
| 選單列圖示 | `MenuBarExtra` + `.window`，SF Symbol `display` |
| 螢幕列表 | CoreGraphics + `NSScreen.localizedName`；內置／外接／主螢幕 |
| 解像度／刷新率 | `CGConfigureDisplayWithDisplayMode` |
| 軟件亮度 | `CGSetDisplayTransferByFormula`；可重設 |
| 常用 | UserDefaults 預設；一鍵套用 |
| 熄屏 | 全黑 borderless window，Esc 退出 |
| **虛擬螢幕（實驗）** | UI＋持久化；`dlsym` 呼叫 `CGVirtualDisplay*`；失敗仍儲存設定；可斷開／刪除；可選 `CGConfigureDisplayMirrorOfDisplay` 鏡像 |

---

## 虛擬螢幕（實驗／SPI-dependent）

macOS **冇公開 API** 做到同 BetterDisplay 一樣嘅系統虛擬顯示器。本專案用：

1. **`CGVirtualDisplay` / `CGVirtualDisplayDescriptor` / `CGVirtualDisplayMode`** — 經 `dlsym` 由 `CoreGraphics.framework` 動態解析（唔硬 link，Stock SDK 冇 header 都可以編譯）。
2. 若符號唔存在或 `Create` 失敗 → 繁中提示：  
   「此 macOS／SDK 未能建立系統虛擬螢幕；已儲存設定。請用有開發者 entitlements 嘅 build 或之後接 private API。」
3. **鏡像**：兩邊都有 `CGDirectDisplayID` 時用 `CGConfigureDisplayMirrorOfDisplay`。
4. **串流／PIP**：UI 標「稍後／需要螢幕錄製權限」，Toggle disabled。

### 點測虛擬螢幕

1. Run app → 「建立虛擬螢幕…」（側欄「虛擬」或底部／標題列 +）。
2. 揀闊高／刷新率／HiDPI、配合實體螢幕；可開「連接後鏡像」。
3. 睇「關於」或虛擬詳情入面 **SPI：符號可用／不可用**。
4. 若 SPI 可用但仍連唔到：多數係 entitlement／系統政策；設定會留低，之後可再撳「連接」。
5. 系統「顯示器」設定睇吓有冇多咗一個 display；「斷開」「刪除」應清走 session 物件。

**Known limitations**

- 唔等同 BetterDisplay 嘅 dummy／AirPlay／私有 framebuffer 方案。
- `CGVirtualDisplayCreate` 可能要唔公開 entitlement；Personal Team Debug 好常見失敗。
- 虛擬解像度 slider 係「改 config → 斷開再連」best-effort。
- 重開 app 唔會自動 reconnect（要手動「連接」）。
- 全螢幕串流未做（要 Screen Recording）。

---

## Roadmap

- ~~虛擬螢幕／dummy display~~ → **實驗性（SPI）已接線；穩定系統虛擬桌面仍待 private API／entitlement**
- 硬件 DDC/CI
- EDID override、XDR nits、PIP／串流、layout protection、CEC
- App Store 沙盒版
- 自訂 app icon PNG

---

## 重要限制／真實硬件要測

1. `CGConfigureDisplayWithDisplayMode`
2. `CGSetDisplayTransferByFormula` / `CGDisplayRestoreColorSyncSettings`
3. `CGDisplayCreateUUIDFromDisplayID` bridging
4. **`CGVirtualDisplay*` via dlsym** + mirror
5. 熄屏 window level

---

## 專案結構

```
FlexDisplay/
├── project.yml
├── Package.swift
├── README.md
├── scripts/generate-xcodeproj.sh
├── Resources/
│   ├── Info.plist
│   ├── FlexDisplay.entitlements
│   └── Assets.xcassets/
└── Sources/FlexDisplay/
    ├── FlexDisplayApp.swift
    ├── DisplayModels.swift
    ├── DisplayService.swift
    ├── FavoritesStore.swift
    ├── BlackoutController.swift
    ├── MenuBarView.swift
    ├── DisplayDetailView.swift
    ├── VirtualDisplayModels.swift
    ├── VirtualDisplayService.swift    # dlsym CGVirtualDisplay*
    ├── CreateVirtualScreenSheet.swift
    └── VirtualScreenDetailView.swift
```

## License

私人／本地使用。BetterDisplay 係 waydabber 獨立產品，本專案無附屬關係。
