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
    var geminiModel: String = "gemini-2.5-flash-lite"
    var geminiMaxContextTokens: Int = 20_000
    var subtitleFontSize: CGFloat = 24
    var subtitleWindowWidth: CGFloat = 0
    var subtitleWindowHeight: CGFloat = 0
    var subtitleWindowOpacity: Double = 0.85
    var subtitleHistoryLimit: Int = 3
    var subtitleAutoOpacityByCount: Bool = true
    var showOriginalText: Bool = true
    var subtitleTextOutlineEnabled: Bool = true

    // MARK: - Deepgram 斷句參數（Phase 1 調整）
    /// 靜音判定時間（毫秒），預設 200ms
    var deepgramEndpointingMs: Int = 200
    /// utterance 超時時間（毫秒），預設 1000ms（Deepgram 最小值為 1000）
    var deepgramUtteranceEndMs: Int = 1000
    /// 最大累積字數，預設 50
    var deepgramMaxBufferChars: Int = 50
    /// interim 無更新超過此秒數即落地為 [暫停]，預設 4.0 秒（由 Profile 帶入，僅用於 runtime）
    var interimStaleTimeoutSec: Double = 4.0

    // MARK: - Profiles
    var profiles: [Profile] = []
    var selectedProfileId: UUID?

    // MARK: - Runtime Only
    /// 翻譯背景資訊（由當前 Profile 帶入，僅用於 runtime）
    var translationContext: String = ""
    /// Deepgram keyterms（由當前 Profile 帶入，僅用於 runtime）
    var deepgramKeyterms: [String] = []
    /// 當前語言（由 Profile 帶入，僅用於 runtime）
    var sourceLanguage: String = "ja"
    var targetLanguage: String = "zh-TW"

    init(
        deepgramApiKey: String = "",
        geminiApiKey: String = "",
        geminiModel: String = "gemini-2.5-flash-lite",
        geminiMaxContextTokens: Int = 20_000,
        subtitleFontSize: CGFloat = 24,
        subtitleWindowWidth: CGFloat = 0,
        subtitleWindowHeight: CGFloat = 0,
        subtitleWindowOpacity: Double = 0.85,
        subtitleHistoryLimit: Int = 3,
        subtitleAutoOpacityByCount: Bool = true,
        showOriginalText: Bool = true,
        subtitleTextOutlineEnabled: Bool = true,
        deepgramEndpointingMs: Int = 200,
        deepgramUtteranceEndMs: Int = 1000,
        deepgramMaxBufferChars: Int = 50,
        interimStaleTimeoutSec: Double = 4.0,
        profiles: [Profile] = [],
        selectedProfileId: UUID? = nil,
        translationContext: String = "",
        deepgramKeyterms: [String] = [],
        sourceLanguage: String = "ja",
        targetLanguage: String = "zh-TW"
    ) {
        self.deepgramApiKey = deepgramApiKey
        self.geminiApiKey = geminiApiKey
        self.geminiModel = geminiModel
        self.geminiMaxContextTokens = geminiMaxContextTokens
        self.subtitleFontSize = subtitleFontSize
        self.subtitleWindowWidth = subtitleWindowWidth
        self.subtitleWindowHeight = subtitleWindowHeight
        self.subtitleWindowOpacity = subtitleWindowOpacity
        self.subtitleHistoryLimit = subtitleHistoryLimit
        self.subtitleAutoOpacityByCount = subtitleAutoOpacityByCount
        self.showOriginalText = showOriginalText
        self.subtitleTextOutlineEnabled = subtitleTextOutlineEnabled
        self.deepgramEndpointingMs = deepgramEndpointingMs
        self.deepgramUtteranceEndMs = deepgramUtteranceEndMs
        self.deepgramMaxBufferChars = deepgramMaxBufferChars
        self.interimStaleTimeoutSec = interimStaleTimeoutSec
        self.profiles = profiles
        self.selectedProfileId = selectedProfileId
        self.translationContext = translationContext
        self.deepgramKeyterms = deepgramKeyterms
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }

    enum CodingKeys: String, CodingKey {
        case deepgramApiKey
        case geminiApiKey
        case geminiModel
        case geminiMaxContextTokens
        case subtitleFontSize
        case subtitleWindowWidth
        case subtitleWindowHeight
        case subtitleWindowOpacity
        case subtitleHistoryLimit
        case subtitleAutoOpacityByCount
        case showOriginalText
        case subtitleTextOutlineEnabled
        case deepgramEndpointingMs
        case deepgramUtteranceEndMs
        case deepgramMaxBufferChars
        case profiles
        case selectedProfileId
        // Legacy keys (migration only)
        case sourceLanguage
        case targetLanguage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        deepgramApiKey = try container.decodeIfPresent(String.self, forKey: .deepgramApiKey) ?? ""
        geminiApiKey = try container.decodeIfPresent(String.self, forKey: .geminiApiKey) ?? ""
        geminiModel = try container.decodeIfPresent(String.self, forKey: .geminiModel) ?? "gemini-2.5-flash-lite"
        geminiMaxContextTokens = try container.decodeIfPresent(Int.self, forKey: .geminiMaxContextTokens) ?? 20_000
        subtitleFontSize = try container.decodeIfPresent(CGFloat.self, forKey: .subtitleFontSize) ?? 24
        subtitleWindowWidth = try container.decodeIfPresent(CGFloat.self, forKey: .subtitleWindowWidth) ?? 0
        subtitleWindowHeight = try container.decodeIfPresent(CGFloat.self, forKey: .subtitleWindowHeight) ?? 0
        subtitleWindowOpacity = try container.decodeIfPresent(Double.self, forKey: .subtitleWindowOpacity) ?? 0.85
        subtitleHistoryLimit = try container.decodeIfPresent(Int.self, forKey: .subtitleHistoryLimit) ?? 3
        subtitleAutoOpacityByCount = try container.decodeIfPresent(Bool.self, forKey: .subtitleAutoOpacityByCount) ?? true
        showOriginalText = try container.decodeIfPresent(Bool.self, forKey: .showOriginalText) ?? true
        subtitleTextOutlineEnabled = try container.decodeIfPresent(Bool.self, forKey: .subtitleTextOutlineEnabled) ?? true
        deepgramEndpointingMs = try container.decodeIfPresent(Int.self, forKey: .deepgramEndpointingMs) ?? 200
        deepgramUtteranceEndMs = try container.decodeIfPresent(Int.self, forKey: .deepgramUtteranceEndMs) ?? 1000
        deepgramMaxBufferChars = try container.decodeIfPresent(Int.self, forKey: .deepgramMaxBufferChars) ?? 50

        let decodedProfiles = try container.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
        let decodedSelectedId = try container.decodeIfPresent(UUID.self, forKey: .selectedProfileId)

        if decodedProfiles.isEmpty {
            let legacySource = try container.decodeIfPresent(String.self, forKey: .sourceLanguage) ?? "ja"
            let legacyTarget = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "zh-TW"
            let legacyProfile = Profile(
                name: "Default",
                translationContext: "",
                keyterms: [],
                sourceLanguage: legacySource,
                targetLanguage: legacyTarget,
                deepgramEndpointingMs: deepgramEndpointingMs,
                deepgramUtteranceEndMs: deepgramUtteranceEndMs,
                deepgramMaxBufferChars: deepgramMaxBufferChars
            )
            profiles = [legacyProfile]
            selectedProfileId = legacyProfile.id
        } else {
            profiles = decodedProfiles
            if let selected = decodedSelectedId,
               decodedProfiles.contains(where: { $0.id == selected }) {
                selectedProfileId = selected
            } else {
                selectedProfileId = decodedProfiles.first?.id
            }
        }

        translationContext = ""
        deepgramKeyterms = []
        if let currentId = selectedProfileId,
           let current = profiles.first(where: { $0.id == currentId }) {
            sourceLanguage = current.sourceLanguage
            targetLanguage = current.targetLanguage
            deepgramEndpointingMs = current.deepgramEndpointingMs
            deepgramUtteranceEndMs = current.deepgramUtteranceEndMs
            deepgramMaxBufferChars = current.deepgramMaxBufferChars
            interimStaleTimeoutSec = current.interimStaleTimeoutSec
        } else {
            sourceLanguage = "ja"
            targetLanguage = "zh-TW"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deepgramApiKey, forKey: .deepgramApiKey)
        try container.encode(geminiApiKey, forKey: .geminiApiKey)
        try container.encode(geminiModel, forKey: .geminiModel)
        try container.encode(geminiMaxContextTokens, forKey: .geminiMaxContextTokens)
        try container.encode(subtitleFontSize, forKey: .subtitleFontSize)
        try container.encode(subtitleWindowWidth, forKey: .subtitleWindowWidth)
        try container.encode(subtitleWindowHeight, forKey: .subtitleWindowHeight)
        try container.encode(subtitleWindowOpacity, forKey: .subtitleWindowOpacity)
        try container.encode(subtitleHistoryLimit, forKey: .subtitleHistoryLimit)
        try container.encode(subtitleAutoOpacityByCount, forKey: .subtitleAutoOpacityByCount)
        try container.encode(showOriginalText, forKey: .showOriginalText)
        try container.encode(subtitleTextOutlineEnabled, forKey: .subtitleTextOutlineEnabled)
        try container.encode(profiles, forKey: .profiles)
        try container.encodeIfPresent(selectedProfileId, forKey: .selectedProfileId)
    }
}
