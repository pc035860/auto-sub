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

    // MARK: - Codable（支援匯入缺少 id 的 JSON）

    enum CodingKeys: String, CodingKey {
        case id, name, translationContext, keyterms
        case sourceLanguage, targetLanguage
        case deepgramEndpointingMs, deepgramUtteranceEndMs, deepgramMaxBufferChars
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // id 若不存在則生成新 UUID（支援匯入沒有 id 的 JSON）
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        translationContext = try container.decode(String.self, forKey: .translationContext)
        keyterms = try container.decode([String].self, forKey: .keyterms)
        sourceLanguage = try container.decode(String.self, forKey: .sourceLanguage)
        targetLanguage = try container.decode(String.self, forKey: .targetLanguage)
        deepgramEndpointingMs = try container.decode(Int.self, forKey: .deepgramEndpointingMs)
        deepgramUtteranceEndMs = try container.decode(Int.self, forKey: .deepgramUtteranceEndMs)
        deepgramMaxBufferChars = try container.decode(Int.self, forKey: .deepgramMaxBufferChars)
    }

    // MARK: - 匯出

    /// 匯出為 JSON Data（不包含 id 欄位）
    func encodeForExport() throws -> Data {
        let exportDict: [String: Any] = [
            "name": name,
            "translationContext": translationContext,
            "keyterms": keyterms,
            "sourceLanguage": sourceLanguage,
            "targetLanguage": targetLanguage,
            "deepgramEndpointingMs": deepgramEndpointingMs,
            "deepgramUtteranceEndMs": deepgramUtteranceEndMs,
            "deepgramMaxBufferChars": deepgramMaxBufferChars
        ]
        return try JSONSerialization.data(withJSONObject: exportDict, options: [.sortedKeys, .prettyPrinted])
    }
}
