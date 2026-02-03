//
//  Profile.swift
//  AutoSub
//
//  轉譯/翻譯 Profile
//

import Foundation

struct Profile: Codable, Identifiable {
    var id: UUID
    var name: String
    var translationContext: String
    var keyterms: [String]
    var sourceLanguage: String
    var targetLanguage: String
    var deepgramEndpointingMs: Int
    var deepgramUtteranceEndMs: Int
    var deepgramMaxBufferChars: Int

    init(
        id: UUID = UUID(),
        name: String = "Default",
        translationContext: String = "",
        keyterms: [String] = [],
        sourceLanguage: String = "ja",
        targetLanguage: String = "zh-TW",
        deepgramEndpointingMs: Int = 200,
        deepgramUtteranceEndMs: Int = 1000,
        deepgramMaxBufferChars: Int = 50
    ) {
        self.id = id
        self.name = name
        self.translationContext = translationContext
        self.keyterms = keyterms
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.deepgramEndpointingMs = deepgramEndpointingMs
        self.deepgramUtteranceEndMs = deepgramUtteranceEndMs
        self.deepgramMaxBufferChars = deepgramMaxBufferChars
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "未命名 Profile" : name
    }
}
