# Auto-Sub 未來功能 Roadmap

> 腦力激盪綜合報告 — 2026-02-15
>
> 由 Core-Proposer（核心技術提案）、Scenario-Proposer（使用場景提案）、Market-Researcher（市場研究）、Tech-Researcher（技術研究）、Devil's Advocate（批判審視）五方意見整合

---

## 執行摘要

本次腦力激盪聚焦 Auto-Sub 的**功能面未來方向**（有別於前兩輪的 UI/UX 改進）。五位 teammates 共提出 14 個功能提案，經 Devil's Advocate 嚴格批判後，精煉為 **2 個立即執行項 + 5 個驗證後執行項 + 2 個低優先項**，否決 5 個提案。

**狀態更新（2026-02-16）**：
- Tier 1 的 **1.1 Streaming Translation 已完成實作並合併**
- Tier 2 的 **2.2 VAD 靜音偵測（最簡版）已完成**
- Tier 2 的 **2.3 SRT 匯出已擴充為最近 5 筆 transcription 可選匯出**（自動儲存待做）

**Devil's Advocate 核心立場**：做 2 件事做到極致，比做 7 件事都半調子好。Auto-Sub 現在最需要的是讓翻譯**更快**出現、讓翻譯**更準確**。其他的，等使用者回饋再說。

---

## 市場背景與技術趨勢（研究摘要）

### 市場洞察

| 發現 | 意義 |
|------|------|
| 大廠（Apple/Google/Microsoft）全都在做即時翻譯，但限在自家生態圈 | Auto-Sub「任意系統音訊」的即時翻譯是真正差異化 |
| Apple Live Translation（macOS Tahoe）將支援日語，但僅限 FaceTime/Messages/Phone | 不直接威脅 Auto-Sub 的核心場景（影片/直播/遊戲） |
| 即時翻譯市場 $1.2B → $3.5B（2026-2033），CAGR 最快 | Auto-Sub 在正確的賽道上 |
| 端側 AI 市場 CAGR 24.6%，whisper.cpp + Metal 已實用 | 混合架構（本地 STT + 雲端翻譯）是可行方向 |
| Otter.ai 達 $100M ARR，從轉錄到 AI Agent 套件 | Agent 化是長期付費方向，但 Auto-Sub 暫時不需要 |
| Transync AI 是最接近的直接競品，但定位偏商務會議 | Auto-Sub 應深耕「日語媒體翻譯」niche |

**來源**：Apple Newsroom、TechCrunch、Google Store、Microsoft Support、BusinessWire、Transync AI、whisper.cpp GitHub

### 關鍵技術動態

| 技術 | 狀態 | 對 Auto-Sub 的影響 |
|------|------|-------------------|
| Apple SpeechAnalyzer（macOS 26） | WWDC 2025 發表，比 Whisper 快 55% | 潛在免費 STT 替代方案，但需 macOS 26 且日語支援待確認 |
| Gemini 2.5 Flash-Lite streaming | sub-100ms TTFT，已 GA | 可大幅降低翻譯延遲 |
| Gemini Live API | 支援直接音訊 → 翻譯 | 長期可跳過 STT 步驟，但有延遲飆升報告 |
| Deepgram nova-3 multilingual | 支援 code-switching | 可解決日語節目穿插英文的問題 |
| LLM vs NMT 翻譯 | LLM 在 WMT24 贏 9/11 語言對 | 確認 Gemini 翻譯是正確方向 |
| MLX Whisper | 比 whisper.cpp 快 30-40%（M1+） | 可作離線 fallback，但即時性仍不如雲端 |

**來源**：MacStories、Google Developers Blog、Deepgram Blog、whisper.cpp benchmarks、MLX Whisper PyPI

---

## Tier 1：立即執行（直接強化核心體驗）

### 1.1 Streaming Translation（翻譯串流輸出）✅ 已完成

**問題**：目前整句送翻譯 → 等翻譯完成才顯示，中間 1-3 秒等待明顯影響體驗。

**方案**：
- 使用 Gemini Streaming API，翻譯結果以 token 為單位串流回來
- 新增 IPC 訊息 `{"type": "translation_streaming", "id": "...", "partial": "部分翻譯..."}`
- SubtitleOverlay 支援串流更新：翻譯文字逐步出現

**批判後調整**：
- ⚠️ 需先驗證 Gemini streaming + Structured Output 的相容性
- ⚠️ 上下文修正在 streaming 模式下的運作方式需先設計
- ⚠️ Gemini Live API 有延遲飆升報告，需有 fallback 機制（退回整句模式）

**相關檔案**：`translator.py:161`（`_send_message_with_timeout`）、`main.py:165-180`（IPC 輸出）
**難度**：中
**依據**：Core-Proposer 提案 C5 + Devil's Advocate 有條件通過 + Tech-Researcher Gemini 延遲數據

**完成狀態（2026-02-15）**：
- 已實作 streaming IPC 訊息 `translation_streaming`（Python backend）
- 已串接 Swift bridge 回呼 `onTranslationStreaming`
- 已在 `AppState.updateStreamingTranslation()` 進行 partial 翻譯更新（僅接受更長 partial，避免舊資料覆蓋）

---

### 1.2 術語庫擴展到翻譯端

**問題**：Profile 的 keyterm 目前只在 Deepgram STT 端使用（`transcriber.py:99-100`），翻譯端沒有結構化術語約束，導致同一個專有名詞可能翻譯不一致。

**方案**：
- 將 Profile 的 keyterm 資訊注入翻譯 prompt（在 `SYSTEM_INSTRUCTION_TEMPLATE` 中加入術語對照）
- 翻譯時自動從 keyterms 中挑選相關術語（不是全部塞，用匹配選 5-10 個）

**批判後縮減**：
- ~~使用者修正累積學習（Dynamic Few-shot）~~ → 不做，UX 破壞即時體驗
- ~~擴展上下文修正窗口~~ → 不做，增加 token 消耗和延遲
- 只做「把已有的 keyterms 也給翻譯端用」，低成本高收益

**相關檔案**：`translator.py:25-33`（`SYSTEM_INSTRUCTION_TEMPLATE`）、`Profile.swift`（keyterms 定義）
**難度**：低
**依據**：Core-Proposer 提案 C4 + Devil's Advocate 縮減版通過

---

## Tier 2：驗證後執行（需數據支持或技術驗證）

### 2.1 多語言辨識 A/B 測試

**問題**：日本節目穿插英文/中文，固定 `ja` 語言設定會遺漏。

**驗證方式**：
- 在測試環境中對比 Deepgram `language="ja"` vs `language="multi"` 的日語 WER
- 如果 multi 模式日語準確率不下降 → 在 Profile 新增 `autoDetectLanguage` 選項
- 如果下降明顯 → 維持現狀，等 Deepgram 改進

**相關檔案**：`transcriber.py:89`（language 設定）
**難度**：低（改一個設定值就能測）
**前提**：需要實測數據

---

### 2.2 VAD 靜音偵測（最簡版）✅ 已完成（2026-02-16）

**問題**：目前所有音訊都送 Deepgram API，包括靜音段，浪費 API 費用。

**方案**：
- 在 `AudioStreamOutput.stream()` 中加入 RMS 閾值判斷（已有 `calculateRMS()`）
- 低於閾值的音訊段不送出（或累積到有語音再送）
- 不做降噪、不做音源分離

**批判後縮減**：
- ~~vDSP 頻譜分析降噪~~ → 不做，Deepgram 自帶降噪
- ~~音源分離~~ → 不做，過度設計
- 只用現有 RMS 做最簡單的靜音過濾

**相關檔案**：`AudioCaptureService.swift:253-266`（`calculateRMS()`）
**難度**：低
**前提**：需測量靜音過濾對 API 成本和 STT 準確率的實際影響

**完成狀態（2026-02-16）**：
- ✅ 已在 `AudioStreamOutput.stream()` 加入 RMS 閾值判斷
- ✅ 低於閾值的音訊段不再送往 Deepgram（僅保留本地音量狀態更新）
- ⏳ 待驗證：實際 API 成本下降幅度與 STT 準確率影響

---

### 2.3 字幕自動儲存 + SRT 匯出（最簡版）🔄 Phase 1 已完成

**問題**：字幕只存記憶體，停止後消失。

**方案**：
- 每次 Session 結束時自動儲存字幕到 JSON 檔（`~/Library/Application Support/AutoSub/sessions/`）
- Menu Bar 新增「匯出上次字幕（SRT）」選項
- 不做歷史瀏覽 UI、不做 SQLite、不做多格式匯出

**批判後縮減**：
- ~~SQLite 持久化~~ → 不做，JSON 檔就夠
- ~~歷史瀏覽 UI~~ → 不做，使用者開 SRT 檔看就好
- ~~TXT + CSV 多格式~~ → 不做，先只做 SRT

**相關檔案**：`AppState.swift`（`subtitleHistory`）、`SubtitleEntry.swift`（已有 Codable）
**難度**：低-中
**前提**：確認使用者確實有回顧字幕的需求

**Phase 1 完成狀態（2026-02-16）**：
- ✅ Menu Bar 新增「匯出為 SRT...」選項
- ✅ 支援三種匯出模式：雙語、僅原文、僅翻譯
- ✅ `sessionSubtitles` 儲存完整 Session（不受 `subtitleHistoryLimit` 限制）
- ✅ 停止擷取後保留字幕內容，開始新 Session 時才清空
- ✅ Menu Bar 匯出改為子選單，可選最近 5 筆 transcription（以開始時間標示）
- ⏳ Phase 2 待做：自動儲存到 JSON（目前 App 關閉後內容消失）

---

### 2.4 Apple SpeechAnalyzer 評估（macOS 26 準備）🔴 現階段不建議採用

**這不是立即實作項，而是技術評估任務。**

Tech-Researcher 發現 Apple 在 WWDC 2025 推出 SpeechAnalyzer API，處理 34 分鐘影片僅 45 秒，比 Whisper 快 55%，原生 Swift API。

**深入評估結果（2026-02-16，5 人團隊研究）**：

| 維度 | SpeechAnalyzer | Deepgram Nova-3 | 勝者 |
|------|---------------|-----------------|------|
| 日語 WER | 無數據（推估 15-20%） | **4.8%**（乾淨）/ 11.9%（噪音） | Deepgram |
| 即時延遲 | ~2.1s（finalized） | **~300ms** | Deepgram |
| Keyterm 提示詞 | ❌ 不支援 | ✅ 最多 100 個 | Deepgram |
| 斷句控制 | ❌ 不可自訂 | ✅ endpointing/utterance_end 可調 | Deepgram |
| 成本 | **免費** | $33.12/月（2h/天） | SpeechAnalyzer |
| 隱私 | **音訊不離開裝置** | 音訊上傳雲端 | SpeechAnalyzer |
| 離線 | **✅ 完全支援** | ❌ 需要網路 | SpeechAnalyzer |

**不建議採用的三大理由**：
1. **延遲**：即時字幕需 <500ms，SpeechAnalyzer 2.1s 不達標（7 倍差距）
2. **Keyterm**：動漫角色名辨識是核心體驗，SpeechAnalyzer 完全不支援（連前代 SFSpeechRecognizer 有的 Custom Vocabulary 都移除了）
3. **日語品質**：零 benchmark，英語 WER 14% 已是商業 STT 中下水準

**Devil's Advocate 補充**：
- 「免費」的隱性成本：遷移工程 2-4 週，雙引擎維護 2-3 倍成本，6-12 個月才回本
- 隱私提升「半真半假」：音訊是系統播放的影音（非私密語音），翻譯文字仍送 Google 雲端
- Apple API 歷史 breaking changes 頻繁（iOS 18.0 破壞 SFSpeechRecognizer），目前仍 Beta 3

**建議行動**：
- **短期**：繼續使用 Deepgram，不投入遷移
- **中期（6-12 個月）**：監控 SpeechAnalyzer 正式版日語表現
- **長期（12+ 個月）**：滿足以下 3/5 條件再啟動 POC
  1. Apple 釋出日語 WER benchmark 且 ≤ 8%
  2. SpeechAnalyzer 正式版穩定 6 個月以上
  3. Apple 加入 Custom Vocabulary / Keyterm 等效功能
  4. macOS 26+ 採用率 > 80%
  5. 有明確成本壓力需削減 Deepgram 費用

**值得保留的想法**：SpeechDetector (VAD) 可獨立使用輔助現有靜音過濾；STT Provider Protocol 抽象層可為未來留彈性（但不急）

**來源**：MacStories 實測、WWDC25 Session 277、Apple 官方文件、Argmax 效能比較、Deepgram 多語言指南、Anton Gubarenko's iOS 26 Guide、Callstack 實作指南

---

## Tier 3：低優先但低風險

### 3.1 Profile 預設模板

**方案**：內建 3-5 個預設 Profile 模板（日劇、動漫、教學/演講），新增 Profile 時可選模板。

**不做的部分**：
- ~~JSON 匯入/匯出~~ → 不做，沒有社群基礎
- ~~社群分享~~ → 不做

**難度**：低
**依據**：Scenario-Proposer S5 + Devil's Advocate 通過（縮減版）

---

### 3.2 使用時長計數器

**方案**：在 Settings 頁面顯示本次 Session 使用時長。使用者可自行去 Deepgram/Google 後台看帳單。

**不做的部分**：
- ~~Python 端回傳精確 token 用量~~ → 不做，增加 IPC 複雜度
- ~~Menu Bar 即時顯示~~ → 不做，系統監控儀表板
- ~~歷史統計~~ → 不做

**難度**：低
**依據**：Scenario-Proposer S3 + Devil's Advocate 縮減版

---

## 否決清單

| 提案 | 否決理由 |
|------|---------|
| C3/S7 離線模式（本地 Whisper + 本地 LLM） | whisper.cpp 即時性不足（small 模型才堪用但準確率低）；本地 LLM 日→繁中品質斷崖下降；維護雙套 pipeline 成本爆炸 |
| C1 Python → Swift 遷移 | 沒有使用者痛點驅動；Python bundled 在 app 裡使用者無感；Swift SDK 成熟度不如 Python；重寫風險高 |
| S2 語言學習輔助模式 | 另一個產品，非核心功能；市場已有成熟工具（Language Reactor、Yomitan） |
| S4 麥克風輸入 | 改變產品定位（系統音訊 → 雙向對話）；需說話者識別；隱私問題放大 |
| S6 字幕主題系統 | 已有背景透明度和字體大小調整；主題系統一旦開始會不斷膨脹 |

---

## 建議執行順序

```
Phase 1（進行中，直接強化核心）
├── ✅ 1.1 Streaming Translation（已完成）
└── ⏳ 1.2 術語庫擴展到翻譯端（低難度，立即改善翻譯一致性）

Phase 2（驗證數據後決定）
├── 2.1 多語言辨識 A/B 測試（改一個設定值）
├── 2.2 VAD 靜音偵測 ✅（利用現有 calculateRMS()，靜音段已過濾）
└── 2.3 字幕匯出 ✅（最近 5 筆可選匯出；自動儲存待做）

Phase 3（低優先，有空再做）
├── 3.1 Profile 預設模板（3-5 個內建模板）
└── 3.2 使用時長計數器

長期觀察
├── Apple SpeechAnalyzer 🔴（已評估，現階段不採用，待日語品質+keyterm支援改善）
├── Gemini Live API（直接音訊→翻譯，等穩定性改善）
└── 混合 Edge+Cloud 架構（本地 STT + 雲端翻譯，待 SpeechAnalyzer 成熟）
```

---

## 差異化定位建議

基於市場研究，Auto-Sub 的獨特定位：

1. **「任意系統音訊」的即時翻譯** — Apple Live Translation 做不到（限自家 app）
2. **日語媒體/動漫/日劇專精** — 大廠不會做的 niche，Profile 系統是獨特優勢
3. **Context-aware 翻譯** — Gemini Chat Session + 上下文修正，品質高於逐句翻譯
4. **桌面覆蓋字幕** — 瀏覽器擴充套件做不到的跨 app 體驗

**短期策略**：深耕日語媒體翻譯，把核心做穩做快（Streaming + 術語）
**中期策略**：混合架構降低成本，多語言 Profile 擴展使用場景
**長期觀察**：Apple SpeechAnalyzer、端到端語音翻譯模型

---

## Devil's Advocate 的最終提醒

> 「做 2 件事做到極致，比做 7 件事都半調子好。Auto-Sub 現在最需要的是讓翻譯更快出現（Streaming Translation）、讓翻譯更準確（術語庫）。其他的，等使用者回饋再說。沒有使用者投訴的問題，就不是問題。」

---

## 與前輪 Brainstorm 的關係

本輪是**功能面 roadmap**，與前兩輪 **UI/UX 改進**（`uiux-roadmap-260215.md`、`uiux-roadmap-260215-2.md`）互補。建議執行順序：

1. **先完成前輪 UI/UX Phase 1-2**（停止淡出、時長顯示、可讀性、resize、Spinner、Profile 選單）
2. **再執行本輪 Phase 1 剩餘項目**（術語庫擴展；Streaming Translation 已完成）
3. **收集使用者回饋**後再決定 Phase 2 項目
