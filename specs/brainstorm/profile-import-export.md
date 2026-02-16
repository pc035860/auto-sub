# 腦力激盪：設定檔匯出匯入功能

> 日期：2026-02-16
> 團隊：proposer-ux、proposer-arch、researcher、critic（devil's advocate）

---

## 綜合結論（批判後改善版）

### 最佳 MVP 方案

以 UX 提案為基礎，經 Devil's Advocate 批判後簡化：

| 項目 | 決策 | 理由 |
|------|------|------|
| **匯出範圍** | 只匯出單個 Profile | Profile 是唯一有分享價值的設定；字幕參數是裝置相關偏好，跨裝置匯入反而會壞 |
| **副檔名** | MVP 用 `.json` | 使用者看到 .json 更安心；自訂副檔名留 Phase 2 做 UTType 時再加 |
| **匯出格式** | 直接 `JSONEncoder().encode(profile)`，不加 wrapper | Profile 已是 Codable，Codable + decodeIfPresent 天然向後相容，不需要 version 欄位 |
| **UUID** | 匯入時生成新 UUID，不匯出原 UUID | 避免 ID 衝突 |
| **衝突處理** | 同名自動加後綴「(2)」 | 最安全的 MVP 選擇；覆蓋是破壞性操作不可接受 |
| **UI 入口** | 設定視窗 Profile Tab | 匯出匯入是低頻操作，放 Menu Bar 佔高頻空間；Profile Tab 已有 CRUD 按鈕 |
| **檔案 Panel** | NSSavePanel / NSOpenPanel + `NSApp.activate()` | LSUIElement App 必須先 activate |
| **預估行數** | ~80-100 行 | 去掉 wrapper format 後更精簡 |

### 匯出格式（極簡版）

匯出的 JSON 就是 Profile struct 本身（去掉 `id`）：

```json
{
  "name": "日劇通用",
  "translationContext": "這是一部日本連續劇...",
  "keyterms": ["田中太郎:たなかたろう", "東京:とうきょう"],
  "sourceLanguage": "ja",
  "targetLanguage": "zh-TW",
  "deepgramEndpointingMs": 200,
  "deepgramUtteranceEndMs": 1000,
  "deepgramMaxBufferChars": 50
}
```

### 匯出流程

1. 使用者在 Profile Tab 選擇一個 Profile，點「匯出」
2. `NSApp.activate()` → `DispatchQueue.main.async` → NSSavePanel
3. 預設檔名：`{profile.name}.json`
4. `JSONEncoder().encode(profile)`（encode 時排除 `id`）→ 寫入檔案

### 匯入流程

1. 使用者點「匯入」
2. `NSApp.activate()` → NSOpenPanel（allowedContentTypes: `.json`）
3. `JSONDecoder().decode(Profile.self, from: data)` → 失敗就 alert
4. 生成新 UUID
5. 檢查同名 → 有就加後綴「(2)」
6. 加入 profiles 陣列，儲存

### UI 示意

```
┌─────────────────────────────────────┐
│ Profile                             │
│ ┌─────────────────────────────────┐ │
│ │ 目前 Profile: [日劇通用 ▾]      │ │
│ ├─────────────────────────────────┤ │
│ │ [新增] [刪除] [匯出↑] [匯入↓]  │ │
│ └─────────────────────────────────┘ │
│ 擷取中無法切換或編輯 Profile          │
└─────────────────────────────────────┘
```

---

## 各提案摘要

### Proposer-UX（UX 提案）

**核心主張**：只匯出 Profile，UI 放設定視窗 Profile Tab

- Profile 是唯一有「分享價值」的設定（朋友看同部日劇，需要相同翻譯背景和 keyterms）
- 字幕參數是個人螢幕偏好，不同螢幕尺寸不通用
- 副檔名 `.autosub-profile`（JSON）
- 匯出加 metadata wrapper：`{ version, exportedAt, app: "AutoSub", profile }`
- 不匯出 UUID，匯入時自動生成
- 同名衝突：MVP 自動加後綴「(2)」，Phase 2 加三選一 dialog
- MVP 估計 ~110 行
- 分享場景：AirDrop / LINE 傳檔案

### Proposer-Arch（架構提案）

**核心主張**：匯出全部設定，新增 ConfigExportData 型別

- 匯出範圍包含 Gemini model、字幕參數 + 所有 Profiles
- UI 入口放 Menu Bar（「匯出設定...」「匯入設定...」）
- 副檔名 `.autosub`
- 匯出加 envelope：`{ formatVersion, appVersion, exportedAt, exportType, configuration }`
- UUID 保留
- 衝突處理：匯入時整包覆蓋所有 Profiles
- 新增型別：`ConfigExportData`、`ConfigImportError`、`ExportType` enum
- ConfigurationService 擴展：`exportConfiguration()` / `importConfiguration()`
- MVP 估計 ~150-200 行
- UTType 註冊 `.autosub`

### Researcher（研究報告）

**業界參考**：

| 工具 | 做法 |
|------|------|
| OBS Studio | JSON 匯出 Scene Collection / Profile，Menu 觸發 |
| Raycast | 加密 `.rayconfig`，社群分享平台 |
| iTerm2 | Dynamic Profiles（JSON/plist），支援剪貼簿匯入 |
| Aegisub | 純 config.json 手動複製，無 GUI |

**技術要點**：
- 格式推薦 JSON（與現有 config.json 一致，Codable 原生支援）
- macOS UTType 自訂副檔名需 Info.plist 宣告（identifier 必須完全一致）
- LSUIElement App 彈 Panel 前必須 `NSApp.activate()`
- 安全：Codable 解碼不執行程式碼，天然安全；Profile 不含 API Key
- 分享 MVP 順序：檔案分享 → 拖放 → URL Scheme → 社群平台

---

## Devil's Advocate 批判重點

### 具體弱點

1. **Arch 提案匯出「全部設定」有 API Key 洩漏風險**：Configuration struct 直接包含 API Key 欄位，安全性依賴「記得清空」而非「結構性不可能」
2. **Arch 提案「整包覆蓋 Profiles」是破壞性操作**：使用者精心設定的 Profile 一匯入就全沒了
3. **UX 提案副檔名 `.autosub-profile` 含連字號**：macOS UTType 對連字號處理不友善
4. **UX 提案加後綴會汙染 Profile 列表**：重複匯入產生「日劇 (2)」「日劇 (3)」...

### 隱藏假設質疑

1. **「使用者會跨裝置分享 Profile」** — 主要場景更可能是備份，匯出全部 Profile 可能更實用
2. **「需要自訂副檔名」** — MVP 用 `.json` 就夠，使用者看到 .json 更安心
3. **「版本相容性是 MVP 要解決的」** — Profile 用 Codable + decodeIfPresent 天然向後相容，不需要 version 欄位

### YAGNI 違規清單

| 項目 | 提案 | 違規程度 |
|---|---|---|
| `formatVersion` / `version` 欄位 | Arch, UX | 中 |
| `appVersion` 欄位 | Arch | 高 |
| `ConfigExportData` 新型別 | Arch | 高 |
| `ConfigImportError` 新型別 | Arch | 中 |
| 匯出全部設定 | Arch | 高 |
| 自訂副檔名（MVP） | UX, Arch | 中 |
| 欄位值範圍驗證 | Researcher | 中 |

---

## Phase 路線圖

### Phase 1 — MVP（本次實作範圍）
- ✅ 單一 Profile 匯出（NSSavePanel → `.json`）
- ✅ 單一 Profile 匯入（NSOpenPanel → 驗證 → 加入列表）
- ✅ 同名衝突自動加後綴
- ✅ UI：Profile Tab 加匯出/匯入按鈕

### Phase 2 — 需求驗證後
- 自訂副檔名 `.autosubprofile` + UTType 註冊（雙擊開啟）
- 衝突確認 dialog（取代 / 新增 / 取消）
- 批次匯出全部 Profiles
- 匯入預覽（先顯示內容再確認）

### Phase 3 — 確認瓶頸後
- 拖放匯入（拖到設定視窗）
- URL Scheme（`autosub://import`）
- 匯出 wrapper 格式（加 version、metadata）
