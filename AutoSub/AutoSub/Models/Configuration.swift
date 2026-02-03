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
    var geminiModel: String = "gemini-2.5-flash-lite-preview-09-2025"
    var sourceLanguage: String = "ja"
    var targetLanguage: String = "zh-TW"
    var subtitleFontSize: CGFloat = 24
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
        geminiModel: String = "gemini-2.5-flash-lite-preview-09-2025",
        sourceLanguage: String = "ja",
        targetLanguage: String = "zh-TW",
        subtitleFontSize: CGFloat = 24,
        showOriginalText: Bool = true,
        deepgramEndpointingMs: Int = 200,
        deepgramUtteranceEndMs: Int = 1000,
        deepgramMaxBufferChars: Int = 50
    ) {
        self.deepgramApiKey = deepgramApiKey
        self.geminiApiKey = geminiApiKey
        self.geminiModel = geminiModel
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.subtitleFontSize = subtitleFontSize
        self.showOriginalText = showOriginalText
        self.deepgramEndpointingMs = deepgramEndpointingMs
        self.deepgramUtteranceEndMs = deepgramUtteranceEndMs
        self.deepgramMaxBufferChars = deepgramMaxBufferChars
    }

    enum CodingKeys: String, CodingKey {
        case deepgramApiKey
        case geminiApiKey
        case geminiModel
        case sourceLanguage
        case targetLanguage
        case subtitleFontSize
        case showOriginalText
        case deepgramEndpointingMs
        case deepgramUtteranceEndMs
        case deepgramMaxBufferChars
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        deepgramApiKey = try container.decodeIfPresent(String.self, forKey: .deepgramApiKey) ?? ""
        geminiApiKey = try container.decodeIfPresent(String.self, forKey: .geminiApiKey) ?? ""
        geminiModel = try container.decodeIfPresent(String.self, forKey: .geminiModel) ?? "gemini-2.5-flash-lite-preview-09-2025"
        sourceLanguage = try container.decodeIfPresent(String.self, forKey: .sourceLanguage) ?? "ja"
        targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "zh-TW"
        subtitleFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .subtitleFontSize) ?? 24
        showOriginalText = try container.decodeIfPresent(Bool.self, forKey: .showOriginalText) ?? true
        deepgramEndpointingMs = try container.decodeIfPresent(Int.self, forKey: .deepgramEndpointingMs) ?? 200
        deepgramUtteranceEndMs = try container.decodeIfPresent(Int.self, forKey: .deepgramUtteranceEndMs) ?? 1000
        deepgramMaxBufferChars = try container.decodeIfPresent(Int.self, forKey: .deepgramMaxBufferChars) ?? 50
    }
}
