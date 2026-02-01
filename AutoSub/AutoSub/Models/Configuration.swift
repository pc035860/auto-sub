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

    init(
        deepgramApiKey: String = "",
        geminiApiKey: String = "",
        sourceLanguage: String = "ja",
        targetLanguage: String = "zh-TW",
        subtitleFontSize: CGFloat = 24,
        subtitleDisplayDuration: TimeInterval = 4.0,
        showOriginalText: Bool = true
    ) {
        self.deepgramApiKey = deepgramApiKey
        self.geminiApiKey = geminiApiKey
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.subtitleFontSize = subtitleFontSize
        self.subtitleDisplayDuration = subtitleDisplayDuration
        self.showOriginalText = showOriginalText
    }
}
