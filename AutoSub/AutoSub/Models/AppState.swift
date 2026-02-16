//
//  AppState.swift
//  AutoSub
//
//  應用程式狀態管理
//

import SwiftUI
import Combine

/// 單次 transcription Session（用於最近匯出記錄）
struct TranscriptionSession: Identifiable, Equatable {
    let id: UUID
    let startTime: Date
    let subtitles: [SubtitleEntry]
}

/// 應用程式狀態
enum AppStatus {
    case idle           // 待機
    case capturing      // 擷取中
    case warning        // 警告（網路不穩等）
    case error          // 錯誤
}

/// 應用程式狀態管理
@MainActor
class AppState: ObservableObject {
    private static let initialProfile = Profile()
    private var pendingSaveTask: Task<Void, Never>?
    private var interimFinalizeTask: Task<Void, Never>?
    private var lastInterimUpdatedAt: Date?
    private let interimStaleTimeoutSeconds: TimeInterval = 2.5
    // MARK: - 運行狀態
    @Published var status: AppStatus = .idle
    @Published var isCapturing: Bool = false
    @Published var captureStartTime: Date?
    @Published var currentSubtitle: SubtitleEntry?
    @Published var isConfigured: Bool = false
    @Published var statusMessage: String?
    @Published var isRecovering: Bool = false
    @Published var recoveryAttempt: Int = 0

    // MARK: - API 設定
    @Published var deepgramApiKey: String = ""
    @Published var geminiApiKey: String = ""
    @Published var geminiModel: String = "gemini-2.5-flash-lite-preview-09-2025"
    @Published var geminiMaxContextTokens: Int = 20_000 {
        didSet {
            if geminiMaxContextTokens < 10_000 {
                geminiMaxContextTokens = 10_000
            } else if geminiMaxContextTokens > 100_000 {
                geminiMaxContextTokens = 100_000
            }
        }
    }

    // MARK: - Profiles
    @Published var profiles: [Profile] = [AppState.initialProfile]
    @Published var selectedProfileId: UUID = AppState.initialProfile.id

    // MARK: - 字幕設定
    @Published var subtitleFontSize: CGFloat = 24
    @Published var subtitleWindowWidth: CGFloat = 0
    @Published var subtitleWindowHeight: CGFloat = 0
    @Published var subtitleWindowOpacity: Double = 0.85
    @Published var subtitleHistoryLimit: Int = 3 {
        didSet {
            if subtitleHistoryLimit < 1 {
                subtitleHistoryLimit = 1
            } else if subtitleHistoryLimit > 30 {
                subtitleHistoryLimit = 30
            }
            trimSubtitleHistoryIfNeeded()
        }
    }
    @Published var subtitleAutoOpacityByCount: Bool = true
    @Published var showOriginalText: Bool = true
    @Published var subtitleTextOutlineEnabled: Bool = true

    // MARK: - 字幕歷史
    /// 字幕歷史記錄（最多保留 30 筆）
    @Published var subtitleHistory: [SubtitleEntry] = []

    // MARK: - Session 匯出用
    /// Session 完整字幕（用於匯出，不受 subtitleHistoryLimit 限制）
    @Published var sessionSubtitles: [SubtitleEntry] = []
    /// 最近 5 筆 transcription（可從 menubar 子選單選擇匯出）
    @Published var recentTranscriptions: [TranscriptionSession] = []

    /// 避免重複歸檔同一個 session
    private var lastArchivedSessionStartTime: Date?

    // MARK: - Interim（正在說的話）
    /// 當前 interim 文字（正在說的話，尚未 final）
    @Published var currentInterim: String?

    // MARK: - 字幕位置
    /// 字幕框是否鎖定
    @Published var isSubtitleLocked: Bool = true

    /// 字幕框位置 X（nil 表示使用預設位置）
    @Published var subtitlePositionX: CGFloat?

    /// 字幕框位置 Y（nil 表示使用預設位置）
    @Published var subtitlePositionY: CGFloat?

    // MARK: - 常數
    // MARK: - 錯誤訊息
    @Published var errorMessage: String?

    // MARK: - Computed Properties

    /// 是否已準備好（API Keys 都已設定）
    var isReady: Bool {
        !deepgramApiKey.isEmpty && !geminiApiKey.isEmpty
    }

    /// 目前選取的 Profile
    var currentProfile: Profile {
        if let profile = profiles.first(where: { $0.id == selectedProfileId }) {
            return profile
        }
        return profiles.first ?? Profile()
    }

    // MARK: - 字幕歷史管理

    /// 新增字幕（原文，翻譯中狀態）
    func addTranscript(id: UUID, text: String) {
        // 清空 interim（已經變成 final 了）
        clearInterim()

        let entry = SubtitleEntry(id: id, originalText: text)
        subtitleHistory.append(entry)

        // 同時加入 sessionSubtitles（用於匯出）
        sessionSubtitles.append(entry)

        // 超過最大數量時移除最舊的
        trimSubtitleHistoryIfNeeded()

        // 同步更新 currentSubtitle（最新的）
        currentSubtitle = entry
    }

    /// 更新字幕翻譯
    /// - Parameters:
    ///   - id: 字幕 ID
    ///   - translation: 翻譯文字
    ///   - wasRevised: 是否為上下文修正（Phase 2）
    func updateTranslation(id: UUID, translation: String, wasRevised: Bool = false) {
        if let index = subtitleHistory.firstIndex(where: { $0.id == id }) {
            // 修復：建立新的 entry 並重新賦值，確保觸發 @Published
            var updatedEntry = subtitleHistory[index]
            updatedEntry.translatedText = translation
            // Phase 2: 若是修正，設定 wasRevised 標記
            if wasRevised {
                updatedEntry.wasRevised = true
            }
            subtitleHistory[index] = updatedEntry

            // 同時更新 sessionSubtitles（用於匯出）
            if let sessionIndex = sessionSubtitles.firstIndex(where: { $0.id == id }) {
                sessionSubtitles[sessionIndex] = updatedEntry
            }

            // 若是最新的，也更新 currentSubtitle
            if updatedEntry.id == currentSubtitle?.id {
                currentSubtitle = updatedEntry
            }
        }
    }

    /// Phase 1B: 更新 streaming 翻譯（即時更新）
    /// - Note: 只接受比現有更長的 partial，避免網路延遲導致舊資料覆蓋新資料
    func updateStreamingTranslation(id: UUID, partial: String) {
        if let index = subtitleHistory.firstIndex(where: { $0.id == id }) {
            let existingLength = subtitleHistory[index].translatedText?.count ?? 0
            // 只接受更長的 partial（防止同長度或更短的舊資料覆蓋）
            guard partial.count > existingLength else {
                return
            }
            var updatedEntry = subtitleHistory[index]
            updatedEntry.translatedText = partial
            subtitleHistory[index] = updatedEntry

            // 同時更新 sessionSubtitles（用於匯出）
            if let sessionIndex = sessionSubtitles.firstIndex(where: { $0.id == id }) {
                sessionSubtitles[sessionIndex] = updatedEntry
            }

            // 若是最新的，也更新 currentSubtitle
            if updatedEntry.id == currentSubtitle?.id {
                currentSubtitle = updatedEntry
            }
        }
    }

    /// 更新 interim 文字（正在說的話）
    func updateInterim(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearInterim()
            return
        }

        currentInterim = text
        let updatedAt = Date()
        lastInterimUpdatedAt = updatedAt
        scheduleInterimFinalizeIfStale(expectedText: text, expectedUpdatedAt: updatedAt)
    }

    /// 清空 interim 文字並取消超時任務
    func clearInterim() {
        interimFinalizeTask?.cancel()
        interimFinalizeTask = nil
        currentInterim = nil
        lastInterimUpdatedAt = nil
    }

    private func trimSubtitleHistoryIfNeeded() {
        if subtitleHistory.count > subtitleHistoryLimit {
            subtitleHistory = Array(subtitleHistory.suffix(subtitleHistoryLimit))
        }
    }

    /// 清空 Session 字幕（開始新 Session 時呼叫）
    func clearSession() {
        clearInterim()
        sessionSubtitles.removeAll()
        subtitleHistory.removeAll()
        currentSubtitle = nil
        captureStartTime = nil
    }

    private func scheduleInterimFinalizeIfStale(expectedText: String, expectedUpdatedAt: Date) {
        interimFinalizeTask?.cancel()

        let timeoutNanoseconds = UInt64(interimStaleTimeoutSeconds * 1_000_000_000)
        interimFinalizeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard let self else { return }
            await MainActor.run {
                guard self.isCapturing else { return }
                guard self.currentInterim == expectedText else { return }
                guard self.lastInterimUpdatedAt == expectedUpdatedAt else { return }

                let finalizedText = expectedText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !finalizedText.isEmpty else {
                    self.clearInterim()
                    return
                }

                // Backend 會在閒置時把 interim 強制落地並翻譯，這裡只做 UI 保底清除，避免卡住。
                self.clearInterim()
            }
        }
    }

    /// 將當前 Session 歸檔到最近 transcription（最多 5 筆）
    func archiveCurrentSessionIfNeeded() {
        guard let startTime = captureStartTime, !sessionSubtitles.isEmpty else {
            return
        }
        guard lastArchivedSessionStartTime != startTime else {
            return
        }

        let archived = TranscriptionSession(
            id: UUID(),
            startTime: startTime,
            subtitles: sessionSubtitles
        )
        recentTranscriptions.insert(archived, at: 0)
        if recentTranscriptions.count > 5 {
            recentTranscriptions = Array(recentTranscriptions.prefix(5))
        }
        lastArchivedSessionStartTime = startTime
    }

    // MARK: - 字幕位置管理

    /// 載入儲存的字幕位置
    func loadSubtitlePosition() {
        // 使用 Double 存取以確保跨平台穩定性
        if UserDefaults.standard.object(forKey: "subtitlePositionX") != nil,
           UserDefaults.standard.object(forKey: "subtitlePositionY") != nil {
            subtitlePositionX = UserDefaults.standard.double(forKey: "subtitlePositionX")
            subtitlePositionY = UserDefaults.standard.double(forKey: "subtitlePositionY")
        }
        isSubtitleLocked = UserDefaults.standard.bool(forKey: "isSubtitleLocked")
    }

    /// 儲存字幕位置
    func saveSubtitlePosition() {
        if let x = subtitlePositionX, let y = subtitlePositionY {
            // 使用 Double 存取以確保跨平台穩定性
            UserDefaults.standard.set(Double(x), forKey: "subtitlePositionX")
            UserDefaults.standard.set(Double(y), forKey: "subtitlePositionY")
        }
        UserDefaults.standard.set(isSubtitleLocked, forKey: "isSubtitleLocked")
    }

    /// 重設字幕位置到預設
    func resetSubtitlePosition() {
        subtitlePositionX = nil
        subtitlePositionY = nil
        UserDefaults.standard.removeObject(forKey: "subtitlePositionX")
        UserDefaults.standard.removeObject(forKey: "subtitlePositionY")
    }

    // MARK: - Profile 管理

    /// 套用設定檔（確保至少一個 Profile）
    func applyProfiles(_ newProfiles: [Profile], selectedProfileId: UUID?) {
        let profilesToUse = newProfiles.isEmpty ? [Profile()] : newProfiles
        profiles = profilesToUse
        if let selected = selectedProfileId,
           profilesToUse.contains(where: { $0.id == selected }) {
            self.selectedProfileId = selected
        } else {
            self.selectedProfileId = profilesToUse.first!.id
        }
    }

    /// 切換 Profile
    func selectProfile(id: UUID) {
        guard !isCapturing else { return }
        selectedProfileId = id
        saveConfiguration()
    }

    /// 新增 Profile
    func addProfile() {
        guard !isCapturing else { return }
        let base = currentProfile
        let newProfile = Profile(
            name: "新 Profile",
            translationContext: "",
            keyterms: [],
            sourceLanguage: base.sourceLanguage,
            targetLanguage: base.targetLanguage,
            deepgramEndpointingMs: base.deepgramEndpointingMs,
            deepgramUtteranceEndMs: base.deepgramUtteranceEndMs,
            deepgramMaxBufferChars: base.deepgramMaxBufferChars
        )
        profiles.append(newProfile)
        selectedProfileId = newProfile.id
        saveConfiguration()
    }

    /// 刪除目前 Profile（至少保留一個）
    func deleteSelectedProfile() {
        guard !isCapturing else { return }
        guard profiles.count > 1 else { return }
        if let index = profiles.firstIndex(where: { $0.id == selectedProfileId }) {
            profiles.remove(at: index)
            selectedProfileId = profiles.first!.id
            saveConfiguration()
        }
    }

    /// 更新目前 Profile
    func updateCurrentProfile(_ update: (inout Profile) -> Void) {
        guard !isCapturing else { return }
        updateProfile(id: selectedProfileId, update)
    }

    // MARK: - 設定儲存

    /// 儲存設定到 Keychain
    func saveConfiguration() {
        let profile = currentProfile
        let config = Configuration(
            deepgramApiKey: deepgramApiKey,
            geminiApiKey: geminiApiKey,
            geminiModel: geminiModel,
            geminiMaxContextTokens: geminiMaxContextTokens,
            subtitleFontSize: subtitleFontSize,
            subtitleWindowWidth: subtitleWindowWidth,
            subtitleWindowHeight: subtitleWindowHeight,
            subtitleWindowOpacity: subtitleWindowOpacity,
            subtitleHistoryLimit: subtitleHistoryLimit,
            subtitleAutoOpacityByCount: subtitleAutoOpacityByCount,
            showOriginalText: showOriginalText,
            subtitleTextOutlineEnabled: subtitleTextOutlineEnabled,
            deepgramEndpointingMs: profile.deepgramEndpointingMs,
            deepgramUtteranceEndMs: profile.deepgramUtteranceEndMs,
            deepgramMaxBufferChars: profile.deepgramMaxBufferChars,
            profiles: profiles,
            selectedProfileId: selectedProfileId,
            translationContext: profile.translationContext,
            deepgramKeyterms: profile.keyterms,
            sourceLanguage: profile.sourceLanguage,
            targetLanguage: profile.targetLanguage
        )
        try? ConfigurationService.shared.saveConfiguration(config)
    }

    /// 更新指定 Profile
    func updateProfile(id: UUID, _ update: (inout Profile) -> Void) {
        guard !isCapturing else { return }
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        update(&profiles[index])
        scheduleSaveConfiguration()
    }

    private func scheduleSaveConfiguration() {
        pendingSaveTask?.cancel()
        pendingSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                self.saveConfiguration()
            }
        }
    }
}
