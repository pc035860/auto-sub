# 腦力激盪：儲存/匯出 Transcription 及翻譯功能

> **日期**：2026-02-15
> **團隊**：feature-designer, ux-researcher, tech-architect, format-expert, devils-advocate
> **主題**：Auto-Sub「儲存/匯出 transcription 及翻譯」功能設計

---

## 執行摘要

5 個角色平行研究後，經 Devil's Advocate 批判，瑠瑠整合出以下結論：

**核心洞察**：批判者指出原始提案有過度工程化傾向（完整 Session 管理系統、3 種匯出格式、獨立 StorageService），MVP 應更精簡。最終採納「超精簡 MVP」路線，先驗證需求再擴展。

**最終建議**：Phase 1 只做「匯出當前 Session as SRT」（約 80 行程式碼），不做持久化儲存。

---

## 1. 市場機會（ux-researcher 發現）

| 競品 | 匯出功能 | 結論 |
|------|----------|------|
| Transcrybe（最接近 Auto-Sub） | ❌ 無 | **差異化機會** |
| macOS Live Captions | ❌ 無 | **使用者痛點** |
| Otter.ai | SRT/TXT/DOCX/PDF（SRT 需付費） | 過度複雜，非目標 |
| Notta | TXT/PDF/DOCX/SRT | 會議場景，不同定位 |

**關鍵發現**：即時字幕工具普遍缺少匯出功能，Auto-Sub 有明確差異化空間。

---

## 2. 使用者場景（feature-designer + ux-researcher）

### 核心場景（高頻）
1. **日劇/日漫觀看後回顧**：看完一集後想回顧雙語字幕、查詢特定台詞
2. **日語學習筆記**：匯出字幕建立 Anki 卡片或個人詞彙表
3. **誤關救援**：不小心關掉 App，希望能找回剛才的字幕

### 次要場景（低頻）
4. **日語會議記錄**：會後匯出完整轉錄做為紀錄
5. **長期學習整理**：管理多次學習 Session 的歷史記錄

### 批判者質疑（已採納）
> 「使用者可能只需要『匯出這一次』+『誤關救援』，而不是『永久保存所有 Session + 完整管理 UI』」

---

## 3. 匯出格式分析（format-expert）

### 格式優先級

| 格式 | 相容性 | 實作難度 | 用途 | 建議階段 |
|------|--------|----------|------|----------|
| **SRT** | 99% 播放器支援 | ⭐ 簡單（50 行） | 字幕檔、Anki、學習工具 | **Phase 1** |
| **TXT** | 100% | ⭐ 極簡（20 行） | 純文字筆記 | Phase 2 |
| **CSV** | 試算表/Anki | ⭐ 簡單（30 行） | 語言學習匯入 | Phase 2 |
| **JSON** | 開發者 | ⭐ 極簡（Codable） | 備份/程式處理 | Phase 2 |
| **ASS** | 專業工具 | ⭐⭐⭐ 中等 | 進階樣式字幕 | Phase 3 |
| **VTT** | 網頁原生 | ⭐⭐ 簡單 | HTML5 影片 | Phase 3 |

### 雙語 SRT 實作（垂直堆疊）
```
1
00:00:07,500 --> 00:00:10,230
こんにちは
你好

2
00:00:10,500 --> 00:00:13,000
今日はいい天気ですね
今天天氣真好呢
```

### 技術要點
- **編碼**：必須 UTF-8（CJK 字元支援）
- **時間戳精度**：毫秒（SRT `HH:MM:SS,mmm`）
- **套件選擇**：自製優先（50 行），不引入 SwiftSubtitles（批判者指出未驗證可靠性）

---

## 4. 技術架構（tech-architect + 批判者修正）

### 資料量估算（已驗證）
- 單筆字幕：~250 bytes
- 1 小時擷取：~360 筆 = **90 KB**
- 4 小時電影：**360 KB**
- 結論：記憶體與磁碟完全不是問題 ✅

### 批判者指出的矛盾（已解決）

| 議題 | feature-designer | tech-architect | 最終決策 |
|------|-----------------|----------------|----------|
| 儲存格式 | JSON Lines（append） | JSON file（完整） | **Phase 1 不持久化**，Phase 2 再決定 |
| StorageService | 需要 | 需要（獨立服務） | **Phase 1 不需要**，直接從記憶體匯出 |
| Session 模型 | 完整模型 | CaptureSession struct | **Phase 1 不需要**，用現有 subtitleHistory |

### 最終架構方案

#### Phase 1：無持久化匯出（採納批判者方案）

```
資料流（匯出時）：
AppState.subtitleHistory → ExportService.exportToSRT() → NSSavePanel → .srt 檔案

需要的改動：
├── 新增：Services/ExportService.swift     (~50 行，SRT 生成)
├── 修改：Models/AppState.swift            (~15 行，匯出方法 + 擴大 history)
└── 修改：MenuBar/MenuBarController.swift  (~20 行，新增匯出 menu item)

總計：約 85 行新增/修改程式碼
```

**關鍵設計決策**：
- `subtitleHistory` 從目前最多 3 筆擴大為「整個 Session 期間所有字幕」（記憶體夠用）
- 停止擷取後，Menu Bar 顯示「Export as SRT...」選項
- 開始新擷取時，清空上一次的 history（或提醒匯出）
- 不需要 StorageService、不需要 CaptureSession 模型、不需要磁碟儲存

#### Phase 2：誤關救援（使用者要求才做）

```
功能：
- 自動暫存最近 3-5 次 Session 到 ~/Library/Application Support/AutoSub/sessions/
- 超過上限自動刪除最舊的
- Menu Bar 加 "Recent Sessions >" submenu

技術：
- 簡單的 JSON 陣列（時間戳 + 字幕陣列，不需要複雜 Session 模型）
- 每筆字幕即時追加寫入（JSON Lines，防 crash 丟失）
- 程式碼量：約 100 行
```

#### Phase 3：完整 Session 管理（確認需求才做）

```
功能（全部需要使用者明確要求）：
- Settings 新增 Sessions & Export Tab
- 多格式匯出（TXT、CSV、JSON）
- Session 搜尋/過濾
- 磁碟空間清理機制
```

---

## 5. 互動設計建議

### Phase 1 UX 流程
```
[使用者停止擷取]
    ↓
[Menu Bar 選單]
├── Start Capture (⌘⇧S)
├── ─────────────
├── Export as SRT...          ← 新增（有字幕時才顯示）
├── ─────────────
├── Hide Subtitles (⌘⇧H)
└── Settings...
    ↓
[點擊 Export as SRT...]
    ↓
[NSSavePanel]
├── 預設檔名：AutoSub_2026-02-15_143052.srt
├── 預設位置：~/Downloads
└── 包含選項：✅ 原文 + 翻譯 / ○ 僅原文 / ○ 僅翻譯
    ↓
[儲存完成，Menu Bar 短暫顯示 ✓]
```

### 設計原則（來自 ux-researcher）
- **一鍵匯出** > 複雜設定面板
- **手動觸發** > 自動儲存（Phase 1）
- **自動檔名** + 可編輯
- 匯出按鈕只在「有字幕可匯出」時啟用

---

## 6. 批判總結與風險清單

### 已解決的風險
| 風險 | 原始方案 | 解決方式 |
|------|---------|----------|
| 過度工程化 | 3 個新檔案 + Session 模型 | Phase 1 精簡為 ~85 行 |
| MVP 範圍膨脹 | 3 種格式 | Phase 1 只做 SRT |
| 儲存格式矛盾 | JSON Lines vs JSON file | Phase 1 不持久化 |
| 外部依賴風險 | SwiftSubtitles 套件 | 自製 SRT（50 行） |

### 待觀察的風險（Phase 2 再處理）
| 風險 | 說明 | 觸發條件 |
|------|------|----------|
| Crash recovery | App crash 時字幕丟失 | 使用者回報資料遺失 |
| 磁碟空間 | 長期累積 Session | 實作持久化儲存後 |
| 大量 Session UI | 100+ Session 管理困難 | 實作 Session 管理後 |
| 並發寫入 | 匯出時同時收到新字幕 | @MainActor 應可保證安全 |

### 批判者的核心提醒
> 「不要假設使用者需要『保存所有歷史』。80% 的使用者可能只需要『匯出這一次』。先做最簡單的，驗證需求後再擴展。」

---

## 7. 最終行動建議

### Phase 1 — 匯出當前 Session（立即可做）
- **範圍**：匯出 SRT（雙語垂直堆疊）
- **工作量**：~85 行程式碼，預估 0.5-1 天
- **前置條件**：擴大 `subtitleHistory` 容量（從 3 筆 → 不限）
- **驗證指標**：使用者是否實際使用匯出功能？匯出頻率？

### Phase 2 — 誤關救援 + 多格式（使用者回饋後）
- **觸發條件**：使用者回報「crash 後資料丟失」或「需要其他格式」
- **工作量**：~100 行（暫存）+ 每種格式 20-50 行
- **技術決策**：此時再決定 JSON Lines vs JSON file

### Phase 3 — 完整 Session 管理（確認瓶頸後）
- **觸發條件**：使用者明確需要歷史記錄管理
- **工作量**：新增 StorageService + SessionHistoryView + 清理機制
- **技術決策**：此時再評估是否需要 SQLite

---

## 附錄：參考資料

### 競品研究
- [Transcrybe](https://transcrybe.app/) - 最接近競品，無匯出功能
- [Otter.ai Export](https://help.otter.ai/hc/en-us/articles/360047733634) - 多格式匯出
- [macOS Live Captions](https://support.apple.com/guide/mac-help/mchldd11f4fd/mac) - 無儲存功能

### 格式規格
- [SRT Format Spec](https://docs.fileformat.com/video/srt/)
- [ASS Format Spec](http://www.tcax.org/docs/ass-specs.htm)
- [SRT vs VTT vs ASS Guide](https://subconverter.com/subtitle-formats-guide-srt-vtt-ass)

### 學習工具整合
- [subs2srs](https://subs2srs.sourceforge.net/) - SRT → Anki 卡片
- [DualSub](https://github.com/bonigarcia/dualsub) - 雙語字幕合併工具
