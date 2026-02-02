//
//  SubtitleEntry.swift
//  AutoSub
//
//  字幕資料模型
//

import Foundation

/// 字幕條目
struct SubtitleEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let originalText: String      // 日文原文
    let translatedText: String    // 翻譯
    let timestamp: Date

    init(original: String, translated: String) {
        self.id = UUID()
        self.originalText = original
        self.translatedText = translated
        self.timestamp = Date()
    }

    static func == (lhs: SubtitleEntry, rhs: SubtitleEntry) -> Bool {
        lhs.id == rhs.id
    }
}
