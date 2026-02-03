//
//  Configuration.swift
//  AutoSub
//
//  設定模型
//

import Foundation

/// 應用程式設定
struct Configuration: Codable {
    var deepgramApiKey: String
    var geminiApiKey: String
    var sourceLanguage: String = "ja"
    var targetLanguage: String = "zh-TW"
    var subtitleFontSize: CGFloat = 24
    var subtitleDisplayDuration: TimeInterval = 4.0
    var showOriginalText: Bool = true

    // MARK: - Deepgram 斷句參數（Phase 1 調整）
    /// 靜音判定時間（毫秒），預設 200ms
    var deepgramEndpointingMs: Int = 200
    /// utterance 超時時間（毫秒），預設 1000ms（Deepgram 最小值為 1000）
    var deepgramUtteranceEndMs: Int = 1000
    /// 最大累積字數，預設 50
    var deepgramMaxBufferChars: Int = 50

    init(
        deepgramApiKey: String = "",
        geminiApiKey: String = "",
        sourceLanguage: String = "ja",
        targetLanguage: String = "zh-TW",
        subtitleFontSize: CGFloat = 24,
        subtitleDisplayDuration: TimeInterval = 4.0,
        showOriginalText: Bool = true,
        deepgramEndpointingMs: Int = 200,
        deepgramUtteranceEndMs: Int = 1000,
        deepgramMaxBufferChars: Int = 50
    ) {
        self.deepgramApiKey = deepgramApiKey
        self.geminiApiKey = geminiApiKey
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.subtitleFontSize = subtitleFontSize
        self.subtitleDisplayDuration = subtitleDisplayDuration
        self.showOriginalText = showOriginalText
        self.deepgramEndpointingMs = deepgramEndpointingMs
        self.deepgramUtteranceEndMs = deepgramUtteranceEndMs
        self.deepgramMaxBufferChars = deepgramMaxBufferChars
    }
}
