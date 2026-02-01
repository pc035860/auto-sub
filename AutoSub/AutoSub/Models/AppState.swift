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

    // MARK: - 錯誤訊息
    @Published var errorMessage: String?

    // MARK: - Computed Properties

    /// 是否已準備好（API Keys 都已設定）
    var isReady: Bool {
        !deepgramApiKey.isEmpty && !geminiApiKey.isEmpty
    }
}
