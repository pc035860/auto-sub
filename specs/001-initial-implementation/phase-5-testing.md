# Phase 5: 測試與收尾

## Goal

完成整合測試、錯誤處理優化、效能驗證，並準備好可發布的版本。

## Prerequisites

- [ ] Phase 4 完成（所有 UI 已整合）
- [ ] App 基本功能可運作

## Tasks

### 5.1 整合測試

- [ ] 測試完整音訊擷取 → 辨識 → 翻譯 → 顯示流程
- [ ] 測試首次使用流程（venv 建立、權限請求）
- [ ] 測試錯誤處理（API Key 錯誤、網路中斷）

### 5.2 效能驗證

- [ ] 測量總延遲（目標 < 2 秒）
- [ ] 測量 CPU 使用率（目標 < 10%）
- [ ] 測量記憶體使用（目標 < 100MB）
- [ ] 長時間運行測試（目標 > 1 小時無崩潰）

### 5.3 錯誤處理優化

- [ ] 完善 Python 程序異常處理
- [ ] 實作自動重連機制
- [ ] 改善錯誤訊息的使用者友善度

### 5.4 UI 打磨

- [ ] 調整字幕顯示時間和動畫
- [ ] 優化 Menu Bar 狀態回饋
- [ ] 確保設定即時生效

### 5.5 文件撰寫

- [ ] 更新 README.md
- [ ] 建立 CLAUDE.md（專案開發指南）
- [ ] 撰寫使用說明

### 5.6 Build 驗證

- [ ] Release build 測試
- [ ] 驗證 Bundle 結構正確
- [ ] 測試從 Finder 直接開啟

## Verification Checklist

### 功能驗證

| 測試項目 | 預期結果 | 通過 |
|---------|---------|------|
| 首次啟動 | 顯示設定視窗/引導 | [ ] |
| 輸入 API Keys | 儲存到 Keychain | [ ] |
| 開始擷取 | Menu Bar 變綠 | [ ] |
| 播放日語音訊 | 字幕顯示 | [ ] |
| 停止擷取 | Menu Bar 恢復 | [ ] |
| 網路中斷 | 顯示警告，不崩潰 | [ ] |
| API Key 錯誤 | 顯示錯誤訊息 | [ ] |
| 快捷鍵 | ⌘+Shift+S 切換擷取 | [ ] |

### 效能驗證

| 指標 | 目標 | 實測值 | 通過 |
|------|------|--------|------|
| 總延遲 | < 2 秒 | ____ | [ ] |
| CPU（擷取中） | < 10% | ____ | [ ] |
| CPU（閒置） | < 1% | ____ | [ ] |
| 記憶體 | < 100MB | ____ | [ ] |
| 長時間運行 | > 1 小時 | ____ | [ ] |

### 使用者體驗

| 項目 | 驗證 |
|------|------|
| 首次設定時間 | < 3 分鐘 |
| 日常使用 | 一鍵開始 |
| 錯誤訊息 | 清楚易懂 |
| 字幕可讀性 | 雙語顯示清晰 |

## Code Examples

### 效能測量（MVP 版本）

MVP 使用外部工具驗證效能，不實作內建測量框架：

**使用 Instruments 測量**：
1. 打開 Xcode → Product → Profile
2. 選擇 Time Profiler 分析 CPU
3. 選擇 Allocations 分析記憶體

**手動延遲測量**：
```swift
// 簡單的 print-based 延遲測量（開發階段使用）
#if DEBUG
let audioTime = Date()
// ... 處理 ...
print("Latency: \(Date().timeIntervalSince(audioTime)) seconds")
#endif
```

> ⚠️ **Phase 2 優化**：內建效能監控儀表板可在 MVP 完成後加入。
```

### 錯誤處理（MVP 版本）

MVP 採用簡單的錯誤處理策略，不實作自動重連：

```swift
class PythonBridgeService {
    private func handleProcessTermination() {
        Task { @MainActor in
            // MVP: 顯示錯誤訊息，讓用戶手動重啟
            onError?("語音服務已停止，請重新開始擷取")
            // 更新狀態
            onStatusChange?("disconnected")
        }
    }
}
```

> ⚠️ **Phase 2 優化**：自動重連機制（指數退避）可在 MVP 完成後加入。
```

## Files Created/Modified

- `AutoSub/README.md` (new)
- `AutoSub/CLAUDE.md` (new)
- 各 Service 檔案可能有小幅修改

## Testing Scenarios

### Scenario 1: 正常使用流程

1. 啟動 App
2. 設定 API Keys
3. 開始擷取
4. 播放 5 分鐘日語影片
5. 停止擷取
6. 結束 App

**預期**：全程無錯誤，字幕正常顯示

### Scenario 2: 錯誤恢復

1. 開始擷取
2. 中途關閉網路
3. 等待 30 秒
4. 恢復網路

**預期**：顯示警告 → 自動重連 → 恢復正常

### Scenario 3: 長時間運行

1. 開始擷取
2. 播放 2 小時日語音訊
3. 每 30 分鐘檢查資源使用

**預期**：無記憶體洩漏，CPU 穩定

## Notes

### 常見問題排查

| 問題 | 可能原因 | 解決方案 |
|------|---------|---------|
| 無字幕顯示 | API Key 錯誤 | 檢查設定 |
| 延遲過高 | 網路問題 | 檢查網路連線 |
| App 崩潰 | Python 程序異常 | 查看 Console.app 日誌 |
| 權限提示 | 首次使用 | 授權螢幕錄製 |

### Release Checklist

- [ ] Version 號設定正確
- [ ] Build 設定為 Release
- [ ] 測試從 DMG 安裝
- [ ] 測試 Gatekeeper 行為（未簽名會被阻擋）
- [ ] 準備 README 說明安裝步驟

### 未來改進（不在 MVP 範圍）

- Developer ID 簽名 + Notarization
- 自動更新機制
- 多語言支援
- 字幕歷史記錄
