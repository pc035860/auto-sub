//
//  PythonBridgeService.swift
//  AutoSub
//
//  Python 子程序管理服務
//  Phase 3 實作
//

import Foundation

/// Python Bridge 服務
@MainActor
class PythonBridgeService: ObservableObject {
    /// 字幕回呼
    var onSubtitle: ((SubtitleEntry) -> Void)?

    /// 錯誤回呼
    var onError: ((String) -> Void)?

    /// 啟動 Python Backend
    func start(config: Configuration) async throws {
        // TODO: Phase 3 實作
        fatalError("Phase 3: PythonBridgeService.start() not implemented")
    }

    /// 停止 Python Backend
    func stop() {
        // TODO: Phase 3 實作
    }

    /// 發送音訊資料
    func sendAudio(_ data: Data) {
        // TODO: Phase 3 實作
    }
}
