# FlexDisplay

類 [BetterDisplay](https://github.com/waydabber/BetterDisplay) 嘅 **macOS 選單列**螢幕工具（MVP v1.1）。

Menu-bar utility for macOS 14+：列舉螢幕、切換解像度／刷新率、軟件（伽瑪）亮度、常用預設、軟熄屏、實驗性虛擬螢幕。

**Bundle ID:** `com.cicadahk.flexdisplay`

> **唔係** BetterDisplay 替代品。本 repo 喺 Linux 只能備齊原始碼／CI；**簽好名嘅 `.app`／`.dmg` 要喺 Mac 或 `macos-14` GitHub Actions runner 先產生。**

---

## 點樣喺 Mac 打開／執行（unsigned Debug）

### 方法 A — XcodeGen

1. 複製／clone 本 repo 去 Mac。
2. `brew install xcodegen` + Xcode 15+
3. `./scripts/generate-xcodeproj.sh` → `open FlexDisplay.xcodeproj`
4. Signing：揀 Team；**App Sandbox 保持 OFF**（display／gamma API）。
5. Run（⌘R）。

### 方法 B — 冇 XcodeGen

新建 macOS App，拖入 `Sources/FlexDisplay/*.swift` 同 `Resources/`，Info.plist 用 `LSUIElement=true`，entitlements sandbox false。

---

## 簽好名嘅 Release（Developer ID · 店外派發）

Menu bar utility 建議用 **Developer ID Application**（Gatekeeper／公網下載），**唔係** Mac App Store（MAS 強制 App Sandbox，會搞斷解像度／伽瑪／虛擬螢幕）。

### 路徑對照

| 路徑 | 證書 | Sandbox | 適用 |
|------|------|---------|------|
| **Developer ID**（本 repo 預設） | Developer ID Application + Developer ID Installer（可選） | **OFF** | 直接派 `.app`／`.dmg`，要 notarize |
| **Mac App Store** | Apple Distribution | **ON**（強制） | 唔適合呢個 app 嘅核心 API；只作文件說明 |

### 本機簽（Mac + Keychain）

```bash
export TEAM_ID=YOUR_TEAM_ID
# 可選：export SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
./scripts/build-signed-mac.sh

# 連 notarize：
export NOTARIZE=1
export APPLE_API_KEY_ID=...
export APPLE_API_ISSUER_ID=...
export APPLE_API_KEY_P8_PATH=/path/to/AuthKey_XXXXXX.p8
./scripts/build-signed-mac.sh
```

產出：`dist/FlexDisplay.app`、`.zip`、`.dmg`。

### GitHub Actions（`macos-14`）

Workflow：[`.github/workflows/macos-signed.yml`](.github/workflows/macos-signed.yml)

- Trigger：`workflow_dispatch` 或 push tag `v*`
- 步驟：XcodeGen → Archive（Developer ID）→ `notarytool` → staple → 上傳 `.zip` + `.dmg` artifact

#### 要加嘅 repo Secrets

| Secret | 說明 |
|--------|------|
| `APPLE_CERTIFICATE_P12_BASE64` | Developer ID Application 證書嘅 `.p12`，再 `base64`（唔好換行） |
| `APPLE_CERTIFICATE_PASSWORD` | 匯出 `.p12` 時設嘅密碼 |
| `APPLE_TEAM_ID` | 10 字元 Team ID（Membership 頁） |
| `APPLE_API_KEY_ID` | App Store Connect API Key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect Issuer ID（UUID） |
| `APPLE_API_KEY_P8` | API Key 嘅 `.p8` **全文**（包括 `BEGIN/END PRIVATE KEY`） |

加完之後：Actions → **macOS Signed Build** → **Run workflow**。

#### 點樣匯出 `.p12`（EN + 繁中）

1. Apple Developer → **Certificates** → 建立 **Developer ID Application**（要有 Developer ID 權限；個人／公司帳先得）。
2. 下載 `.cer`，喺 Mac 雙擊安裝入 **login** Keychain。
3. Keychain Access → My Certificates → 展開證書 → 揀私鑰 → 右鍵 **Export…** → `.p12`，設密碼。
4. Base64（Mac）：
   ```bash
   base64 -i DeveloperID.p12 | pbcopy
   ```
   貼去 GitHub Secret `APPLE_CERTIFICATE_P12_BASE64`。
5. **App ID**：Developer → Identifiers → App IDs → 登記 `com.cicadahk.flexdisplay`（macOS）。Developer ID 派發唔一定要開 Capability，但預先登記 Bundle ID 方便管理。

#### App Store Connect API Key

1. App Store Connect → Users and Access → **Integrations** → App Store Connect API → **+** Key（Developer / App Manager）。
2. 下載一次性 `.p8`；記低 Key ID + Issuer ID。
3. 將 `.p8` 原文貼去 `APPLE_API_KEY_P8`（CI 用）；本機 notarize 用檔案路徑。

**千萬唔好** commit `.p12`／`.p8`／密碼入 git。

---

## 已實作

| 功能 | 說明 |
|------|------|
| 選單列 | `MenuBarExtra` + `.window` |
| 螢幕／解像度／HiDPI | CoreGraphics |
| 軟件亮度 | gamma formula |
| 常用／熄屏 | UserDefaults / black window |
| 虛擬螢幕（實驗） | `dlsym` → `CGVirtualDisplay*` |
| 簽發 CI | Developer ID + notarytool workflow |

## 虛擬螢幕（實驗／SPI）

見前版說明：`CGVirtualDisplay` 經 dlsym；符號／entitlement 唔夠就只儲存設定。

## Roadmap

- 虛擬螢幕穩定化（private API／entitlement）
- DDC/CI、EDID、XDR、PIP 串流
- MAS 路徑（若果放棄非沙盒 API）

## 專案結構

```
FlexDisplay/
├── .github/workflows/macos-signed.yml
├── project.yml                      # bundle id: com.cicadahk.flexdisplay
├── scripts/generate-xcodeproj.sh
├── scripts/build-signed-mac.sh      # 本機簽
├── Resources/
└── Sources/FlexDisplay/
```

## License

私人／本地使用。BetterDisplay 無附屬關係。
