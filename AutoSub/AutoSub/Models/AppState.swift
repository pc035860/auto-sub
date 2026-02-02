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
    @Published var sourceLanguage: String = "ja"
    @Published var targetLanguage: String = "zh-TW"

    // MARK: - 字幕設定
    @Published var subtitleFontSize: CGFloat = 24
    @Published var subtitleDisplayDuration: TimeInterval = 4.0
    @Published var showOriginalText: Bool = true

    // MARK: - 字幕歷史
    /// 字幕歷史記錄（最多保留 3 筆）
    @Published var subtitleHistory: [SubtitleEntry] = []

    // MARK: - 字幕位置
    /// 字幕框是否鎖定
    @Published var isSubtitleLocked: Bool = true

    /// 字幕框位置 X（nil 表示使用預設位置）
    @Published var subtitlePositionX: CGFloat?

    /// 字幕框位置 Y（nil 表示使用預設位置）
    @Published var subtitlePositionY: CGFloat?

    // MARK: - 常數
    /// 最大歷史記錄數量
    static let maxHistoryCount = 3

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
        let entry = SubtitleEntry(id: id, originalText: text)
        subtitleHistory.append(entry)

        // 超過最大數量時移除最舊的
        if subtitleHistory.count > Self.maxHistoryCount {
            subtitleHistory.removeFirst()
        }

        // 同步更新 currentSubtitle（最新的）
        currentSubtitle = entry
    }

    /// 更新字幕翻譯
    func updateTranslation(id: UUID, translation: String) {
        if let index = subtitleHistory.firstIndex(where: { $0.id == id }) {
            subtitleHistory[index].translatedText = translation

            // 若是最新的，也更新 currentSubtitle
            if subtitleHistory[index].id == currentSubtitle?.id {
                currentSubtitle = subtitleHistory[index]
            }
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
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            subtitleFontSize: subtitleFontSize,
            subtitleDisplayDuration: subtitleDisplayDuration,
            showOriginalText: showOriginalText
        )
        try? ConfigurationService.shared.saveConfiguration(config)
    }
}
