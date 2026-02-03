//
//  AppState.swift
//  AutoSub
//
//  應用程式狀態管理
//

import SwiftUI
import Combine

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
    // MARK: - 運行狀態
    @Published var status: AppStatus = .idle
    @Published var isCapturing: Bool = false
    @Published var currentSubtitle: SubtitleEntry?
    @Published var isConfigured: Bool = false

    // MARK: - API 設定
    @Published var deepgramApiKey: String = ""
    @Published var geminiApiKey: String = ""
    @Published var geminiModel: String = "gemini-2.5-flash-lite-preview-09-2025"
    @Published var sourceLanguage: String = "ja"
    @Published var targetLanguage: String = "zh-TW"

    // MARK: - 字幕設定
    @Published var subtitleFontSize: CGFloat = 24
    @Published var subtitleWindowWidth: CGFloat = 0
    @Published var subtitleWindowHeight: CGFloat = 0
    @Published var subtitleWindowOpacity: Double = 0.7
    @Published var subtitleHistoryLimit: Int = 3 {
        didSet {
            if subtitleHistoryLimit < 1 {
                subtitleHistoryLimit = 1
            } else if subtitleHistoryLimit > 6 {
                subtitleHistoryLimit = 6
            }
            trimSubtitleHistoryIfNeeded()
        }
    }
    @Published var subtitleAutoOpacityByCount: Bool = true
    @Published var showOriginalText: Bool = true

    // MARK: - 字幕歷史
    /// 字幕歷史記錄（最多保留 3 筆）
    @Published var subtitleHistory: [SubtitleEntry] = []

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

    // MARK: - 字幕歷史管理

    /// 新增字幕（原文，翻譯中狀態）
    func addTranscript(id: UUID, text: String) {
        // 清空 interim（已經變成 final 了）
        currentInterim = nil

        let entry = SubtitleEntry(id: id, originalText: text)
        subtitleHistory.append(entry)

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

            // 若是最新的，也更新 currentSubtitle
            if updatedEntry.id == currentSubtitle?.id {
                currentSubtitle = updatedEntry
            }
        }
    }

    /// 更新 interim 文字（正在說的話）
    func updateInterim(_ text: String) {
        currentInterim = text
    }

    private func trimSubtitleHistoryIfNeeded() {
        if subtitleHistory.count > subtitleHistoryLimit {
            subtitleHistory = Array(subtitleHistory.suffix(subtitleHistoryLimit))
        }
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

    // MARK: - 設定儲存

    /// 儲存設定到 Keychain
    func saveConfiguration() {
        let config = Configuration(
            deepgramApiKey: deepgramApiKey,
            geminiApiKey: geminiApiKey,
            geminiModel: geminiModel,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            subtitleFontSize: subtitleFontSize,
            subtitleWindowWidth: subtitleWindowWidth,
            subtitleWindowHeight: subtitleWindowHeight,
            subtitleWindowOpacity: subtitleWindowOpacity,
            subtitleHistoryLimit: subtitleHistoryLimit,
            subtitleAutoOpacityByCount: subtitleAutoOpacityByCount,
            showOriginalText: showOriginalText
        )
        try? ConfigurationService.shared.saveConfiguration(config)
    }
}
