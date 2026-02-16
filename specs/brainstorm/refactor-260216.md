# Auto-Sub Refactoring CP 值分析

> **日期**：2026-02-16
> **團隊**：Swift 架構分析師、Python 架構研究員、Devil's Advocate（批判者）
> **方法**：三方腦力激盪 → 批判修正 → Lead 綜合

---

## 專案現況

| 層級 | 檔案數 | 行數 | 最大檔案 |
|------|--------|------|----------|
| Swift 前端 | 19 | 5,293 | MenuBarController.swift (1,012) |
| Python Backend | 3 核心 | 1,325 | translator.py (676) |
| **合計** | **22** | **6,618** | — |

**現狀評估**：專案運作穩定，無明確維護痛點。程式碼規模適中，尚未到「不重構就無法維護」的程度。

---

## 綜合 CP 值排名

整合三方意見後，瑠瑠將所有提案分為三個 Tier。

### Tier 1 — 推薦執行（低風險高回報）✅ 已完成

#### 1. 簡化 main.py `on_transcript` 回呼函數 ✅

| 項目 | 說明 |
|------|------|
| **目標** | `main.py:118-210`（93 行巢狀回呼） |
| **問題** | 混合翻譯呼叫、streaming 回呼定義、重試、錯誤處理、狀態更新 |
| **方案** | 提取 2-3 個 helper 函數（`translate_with_retry`、`handle_translation_result`），**保持在同一檔案** |
| **不做** | 不建立 `TranslationHandler` 類別（過度設計） |
| **Cost** | 1-2 小時 |
| **收益** | 可讀性大幅提升、重試邏輯可獨立理解 |
| **風險** | 極低（內部重構，不改公開介面） |
| **修正 CP** | **3.0**（提案者 4.0、批判者 2.0） |
| **完成日期** | 2026-02-16 |
| **實際結果** | 93 行 → 46 行（縮減 50%），巢狀深度 4 層 → 2 層，提取 4 個 helper 函數 |

> **三方共識**：所有人都同意這是最值得做的項目。分歧在於要不要建類別——批判者認為 helper 函數就夠，瑠瑠同意這個判斷。

---

#### 2. MenuBarController 局部簡化 ✅

| 項目 | 說明 |
|------|------|
| **目標** | `MenuBarController.swift`（1,012 行） |
| **問題** | `startCapture()` 123 行、8 個回呼設定混在一起 |
| **方案** | 提取 `setupCallbacks()` 和 `buildConfiguration()` 等 helper 方法，**保持在同一檔案** |
| **不做** | 不拆檔案、不建 CaptureCoordinator、不動 Recovery 邏輯 |
| **Cost** | 半天 |
| **收益** | `startCapture()` 從 123 行降至 ~30 行，可讀性提升 |
| **風險** | 低（同檔內提取方法，行為不變） |
| **修正 CP** | **2.5**（提案者 3.5、批判者 1.5） |
| **完成日期** | 2026-02-16 |
| **實際結果** | `startCapture()` 123 行 → 58 行，提取 4 個 helper 方法（`buildConfiguration`、`setupBridgeCallbacks`、`setupAudioDataCallback`、`clearCallbacks`） |

> **批判者觀點**：MenuBarController 包含 4 個類別定義（含 AppDelegate），不是單一 God Object。1012 行中扣除多類別後，每個類別其實不算過大。
>
> **Lead 判斷**：同意不需要拆檔，但 `startCapture()` 的回呼設定確實可讀性差，局部 helper 提取是合理的最小改動。

---

### Tier 2 — 有條件推薦（視需求觸發）

#### 3. 拆分 SettingsView 為獨立檔案

| 項目 | 說明 |
|------|------|
| **目標** | `SettingsView.swift`（559 行，5 個 Tab View） |
| **方案** | 每個 Tab View 拆為獨立 `.swift` 檔案 |
| **觸發條件** | 當需要新增 Settings Tab 或大幅修改 Profile 編輯 UI 時 |
| **不做** | 不建 ViewModel、不做 Property Wrapper（目前不需要） |
| **修正 CP** | **1.5**（提案者 4.0、批判者 1.5） |

> **批判者觀點**：TabView 已經分離職責，只是「在同一檔案」，不影響維護。
>
> **Lead 判斷**：同意現在不急，但如果要動 Settings UI 時順手拆是合理的。

---

#### 4. 統一 Python Backend 錯誤類型

| 項目 | 說明 |
|------|------|
| **目標** | 三個 Python 檔案的錯誤處理 |
| **方案** | 新增 `errors.py`，定義 `AutoSubError` 階層 |
| **觸發條件** | 當需要新增錯誤類型或改進前端錯誤顯示時 |
| **修正 CP** | **1.0**（提案者 1.5、批判者 1.0） |

> 目前錯誤處理雖然不一致，但功能正常。等有具體需求再統一。

---

### Tier 3 — 暫不建議（成本 > 收益）

| # | 提案 | 原始 CP | 修正 CP | 暫緩理由 |
|---|------|---------|---------|----------|
| 5 | 拆解 translator.py God Object | 1.67 | 0.5 | 批判者指出：translator 職責單一（翻譯），行數多不等於職責多。拆分後狀態同步（`_chat`、`_total_tokens`）風險高。 |
| 6 | 簡化 SubtitleOverlay 高度管理 | 2.5 | 1.0 | 高度管理邏輯雖複雜但已穩定運作，提取後導航成本增加、收益有限。 |
| 7 | 模組化 AudioCaptureService | 2.5 | 1.0 | 音訊處理是 hot path，重構有效能風險。目前 496 行不算過大。 |
| 8 | 設計模式基礎設施 | 3.0 | 0.5 | 典型預測性設計。等出現 3+ 相似模式再抽象。 |
| 9 | Circuit Breaker 重試模式 | 1.0 | 0.5 | 目前 3 次重試夠用，無 rate limit 問題報告。 |
| 10 | 改用 asyncio | 1.0 | **-1.0** | **負價值**。完全重寫並發模型，極高 regression 風險，無明確收益。 |

---

## 執行計畫

### 立即可做（~1 天）✅ 已完成 (2026-02-16)

```
Phase 1: main.py 回呼簡化 ✅
├── 提取 translate_with_retry() helper
├── 提取 send_subtitle() helper
├── 提取 send_translation_update() helper
├── 提取 send_translation_error() helper
├── 驗證行為不變（9 個單元測試通過）
└── 實際：~30 分鐘

Phase 2: MenuBarController 局部簡化 ✅
├── 提取 buildConfiguration() 方法
├── 提取 setupBridgeCallbacks() 方法
├── 提取 setupAudioDataCallback() 方法
├── 提取 clearCallbacks() 方法
├── startCapture() 降至 ~58 行
├── 編譯驗證通過
└── 實際：~45 分鐘
```

### 按需觸發

```
觸發：需要修改 Settings UI
└── 拆分 SettingsView 為獨立檔案

觸發：需要改進錯誤處理/顯示
└── 統一 Python Backend 錯誤類型
```

---

## 關鍵決策記錄

### 為什麼大部分提案被降級？

1. **專案規模不需要企業級架構**：6,618 行的專案不需要 Coordinator、Strategy、Circuit Breaker 等模式
2. **穩定性 > 整潔性**：專案運作正常，重構帶來的 regression 風險大於收益
3. **YAGNI 原則**：Property Wrapper、asyncio、統一協議都是「可能未來需要」
4. **最小改動原則**：helper 函數 > 新類別 > 新檔案 > 新架構

### 批判者的核心洞察

> 「現在最大的風險是『過度重構』，而不是『代碼品質』。」

這句話點出了 refactoring 討論中常見的陷阱：**把「可以更好」當成「需要更好」**。在沒有明確維護痛點的情況下，保持穩定比追求整潔更有價值。

---

## 附錄：原始提案 vs 修正 CP 值

| 提案 | 提案者 CP | 批判者 CP | Lead 修正 CP | 變化 |
|------|-----------|-----------|--------------|------|
| main.py 回呼簡化 | 4.0 | 2.0 | **3.0** | -25% |
| MenuBarController 局部簡化 | 3.5 | 1.5 | **2.5** | -29% |
| SettingsView 拆分 | 4.0 | 1.5 | **1.5** | -63% |
| 統一錯誤類型 | 1.5 | 1.0 | **1.0** | -33% |
| translator.py 拆解 | 1.67 | 0.3 | **0.5** | -70% |
| SubtitleOverlay 簡化 | 2.5 | 1.0 | **1.0** | -60% |
| AudioCaptureService 模組化 | 2.5 | 1.0 | **1.0** | -60% |
| 設計模式基礎設施 | 3.0 | 0.5 | **0.5** | -83% |
| Circuit Breaker | 1.0 | 0.5 | **0.5** | -50% |
| 改用 asyncio | 1.0 | -1.0 | **-1.0** | -200% |
