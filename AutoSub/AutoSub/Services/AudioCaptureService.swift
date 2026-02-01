//
//  AudioCaptureService.swift
//  AutoSub
//
//  ScreenCaptureKit 音訊擷取服務
//  Phase 2 實作
//

import Foundation
import ScreenCaptureKit
import AVFoundation

/// 音訊擷取錯誤
enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case noDisplay
    case streamFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "請授權螢幕錄製權限"
        case .noDisplay: return "找不到顯示器"
        case .streamFailed: return "音訊擷取失敗"
        }
    }
}

/// 音訊擷取服務
@MainActor
class AudioCaptureService: NSObject, ObservableObject {
    // 音訊格式：24kHz, 16-bit, Stereo
    let sampleRate: Double = 24000
    let channels: Int = 2
    let bytesPerSample: Int = 2

    /// 音訊資料回呼
    var onAudioData: ((Data) -> Void)?

    /// 開始擷取
    func startCapture() async throws {
        // TODO: Phase 2 實作
        fatalError("Phase 2: AudioCaptureService.startCapture() not implemented")
    }

    /// 停止擷取
    func stopCapture() async {
        // TODO: Phase 2 實作
    }
}
