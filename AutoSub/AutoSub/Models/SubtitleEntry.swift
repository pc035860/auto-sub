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
    var originalText: String       // 日文原文
    var translatedText: String?    // 翻譯（nil 表示翻譯中）
    let timestamp: Date
    var wasRevised: Bool = false   // Phase 2: 標記是否被上下文修正過

    /// 是否正在翻譯中
    var isTranslating: Bool {
        translatedText == nil
    }

    /// 建立僅含原文的條目（收到 transcript 時）
    init(id: UUID = UUID(), originalText: String, timestamp: Date = Date()) {
        self.id = id
        self.originalText = originalText
        self.translatedText = nil
        self.timestamp = timestamp
        self.wasRevised = false
    }

    /// 建立完整條目（收到 subtitle 時，用於更新）
    init(id: UUID, originalText: String, translatedText: String, timestamp: Date = Date(), wasRevised: Bool = false) {
        self.id = id
        self.originalText = originalText
        self.translatedText = translatedText
        self.timestamp = timestamp
        self.wasRevised = wasRevised
    }

    static func == (lhs: SubtitleEntry, rhs: SubtitleEntry) -> Bool {
        lhs.id == rhs.id &&
        lhs.originalText == rhs.originalText &&
        lhs.translatedText == rhs.translatedText &&
        lhs.wasRevised == rhs.wasRevised
    }
}
