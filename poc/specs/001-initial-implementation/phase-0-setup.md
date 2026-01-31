# Phase 0: 專案設置

## Goal

建立 AutoSub macOS App 的 Xcode 專案結構，配置 Bundle 資源和基本設定。

## Prerequisites

- [x] PRD.md 和 SPEC.md 已完成
- [x] macOS 13.0+ 開發環境
- [x] Xcode 15+ 已安裝

## Tasks

### 0.1 建立 Xcode 專案

- [ ] 建立 macOS App 專案（SwiftUI）
- [ ] 專案名稱：`AutoSub`
- [ ] 語言：Swift
- [ ] 最低部署目標：macOS 13.0
- [ ] 組織 ID 設定

### 0.2 專案結構設置

- [ ] 建立目錄結構：
  ```
  AutoSub/
  ├── Models/
  ├── Views/
  ├── Services/
  ├── Utilities/
  └── Resources/
      └── backend/
  ```

### 0.3 Info.plist 配置

- [ ] 設定 `LSUIElement = true`（隱藏 Dock 圖示）
- [ ] 設定 `LSMinimumSystemVersion = 13.0`
- [ ] 設定 `NSScreenCaptureUsageDescription`（螢幕錄製權限說明）

### 0.4 Entitlements 配置

- [ ] 建立 `AutoSub.entitlements`
- [ ] 設定 `com.apple.security.app-sandbox = false`
- [ ] 設定 `com.apple.security.automation.apple-events = true`

### 0.5 Backend 資源配置

- [ ] 在 Resources 中建立 `backend/` 目錄
- [ ] 配置 Copy Bundle Resources 包含 backend 檔案

## Code Examples

### Info.plist 關鍵設定

```xml
<key>LSUIElement</key>
<true/>

<key>LSMinimumSystemVersion</key>
<string>13.0</string>

<key>NSScreenCaptureUsageDescription</key>
<string>Auto-Sub 需要存取螢幕錄製權限以擷取系統音訊</string>
```

### Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

## Verification

### 驗證命令

```bash
# 在專案目錄執行
xcodebuild -project AutoSub.xcodeproj -scheme AutoSub -configuration Debug build
```

### Expected Outcomes

- [ ] Xcode 專案可成功 build
- [ ] 目錄結構符合 SPEC 定義
- [ ] Info.plist 設定正確
- [ ] Entitlements 設定正確
- [ ] backend/ 目錄會被複製到 App Bundle

## Files Created/Modified

- `AutoSub/AutoSub.xcodeproj/` (new)
- `AutoSub/AutoSub/` (new - 主要程式碼目錄)
- `AutoSub/AutoSub/Info.plist` (new)
- `AutoSub/AutoSub.entitlements` (new)
- `AutoSub/AutoSub/Resources/backend/` (new - 空目錄)

## Notes

### Menu Bar App 注意事項

- `LSUIElement = true` 會讓 App 不顯示在 Dock
- 需要使用 `MenuBarExtra` Scene 來建立 Menu Bar 圖示
- macOS 13+ 才支援 `MenuBarExtra`

### Sandbox 說明

- 由於需要執行外部 Python 程序，無法使用 App Sandbox
- 這意味著無法上架 Mac App Store（但這是預期的，見 PRD）
- 獨立發布需要 Developer ID 簽名 + Notarization

### Phase 0 + 1 合併建議

此 Phase 可與 Phase 1 在同一 Session 完成：
- Phase 0 建立專案框架 (~1-2 小時)
- Phase 1 複製並調整 Python Backend (~2-3 小時)
