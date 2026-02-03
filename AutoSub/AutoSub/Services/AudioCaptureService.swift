//
//  AudioCaptureService.swift
//  AutoSub
//
//  ScreenCaptureKit 音訊擷取服務
//  Phase 2 實作
//

import Foundation
import ScreenCaptureKit
@preconcurrency import AVFoundation
@preconcurrency import AVFAudio
import CoreMedia

// MARK: - AudioCaptureError

/// 音訊擷取錯誤
enum AudioCaptureError: Error, LocalizedError {
    case permissionDenied
    case noDisplay
    case streamFailed(Error)
    case converterInitFailed

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "請授權螢幕錄製權限"
        case .noDisplay:
            return "找不到顯示器"
        case .streamFailed(let error):
            return "音訊擷取失敗: \(error.localizedDescription)"
        case .converterInitFailed:
            return "音訊轉換器初始化失敗"
        }
    }
}

// MARK: - AudioStreamOutput

/// SCStreamOutput delegate，處理音訊樣本轉換
final class AudioStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
    // MARK: - Public Properties

    /// 音訊資料回呼
    var onAudioData: ((Data) -> Void)?

    /// 音量回呼（RMS 值，0.0 - 1.0）
    var onVolumeLevel: ((Float) -> Void)?

    /// 錯誤回呼（P4: 讓上層知道錯誤）
    var onError: ((Error) -> Void)?

    // MARK: - Private Properties

    // 音訊轉換器（延遲初始化）
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?

    // 目標格式（聲道數會從源取得）
    private let targetSampleRate: Double = 24_000

    // 轉換器初始化失敗標記
    private var converterInitFailed: Bool = false
    private var hasReportedInitFailure: Bool = false

    // 錯誤記錄（避免大量 log，每 100 幀記錄一次）
    private var errorCount: Int = 0
    private let errorLogInterval: Int = 100

    // MARK: - Init

    init(
        onAudioData: ((Data) -> Void)? = nil,
        onVolumeLevel: ((Float) -> Void)? = nil,
        onError: ((Error) -> Void)? = nil
    ) {
        self.onAudioData = onAudioData
        self.onVolumeLevel = onVolumeLevel
        self.onError = onError
        super.init()
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        // 只處理音訊
        guard outputType == .audio else { return }

        // P3: 如果轉換器初始化失敗，不再處理
        if converterInitFailed {
            reportInitFailureOnce()
            return
        }

        do {
            try sampleBuffer.withAudioBufferList { abl, _ in
                guard let desc = sampleBuffer.formatDescription?.audioStreamBasicDescription else {
                    return
                }

                // 延遲初始化轉換器
                if converter == nil {
                    initializeConverter(from: desc)
                    if converterInitFailed {
                        reportInitFailureOnce()
                        return
                    }
                }

                guard let converter = converter,
                      let outFmt = outputFormat else { return }

                // 建立 source buffer（每次新建，與 POC 一致）
                let srcFmt = converter.inputFormat
                guard let srcBuffer = AVAudioPCMBuffer(
                    pcmFormat: srcFmt,
                    frameCapacity: AVAudioFrameCount(sampleBuffer.numSamples)
                ) else { return }
                srcBuffer.frameLength = srcBuffer.frameCapacity

                // 複製音訊資料
                copyAudioData(from: abl, to: srcBuffer)

                // 建立 output buffer（每次新建，與 POC 一致）
                let outputFrameCapacity = AVAudioFrameCount(
                    ceil(Double(srcBuffer.frameLength) * outFmt.sampleRate / srcFmt.sampleRate)
                )
                guard let outBuffer = AVAudioPCMBuffer(
                    pcmFormat: outFmt,
                    frameCapacity: outputFrameCapacity
                ) else { return }

                // 執行轉換
                var error: NSError?
                let status = converter.convert(to: outBuffer, error: &error) { _, outStatus in
                    outStatus.pointee = .haveData
                    return srcBuffer
                }

                guard status != .error,
                      outBuffer.frameLength > 0,
                      let int16Data = outBuffer.int16ChannelData?[0] else {
                    return
                }

                // 轉換為 Data
                let byteCount = Int(outBuffer.frameLength) * Int(outFmt.streamDescription.pointee.mBytesPerFrame)
                let pcmData = Data(bytes: int16Data, count: byteCount)

                // 計算 RMS 音量
                let rms = calculateRMS(pcmData)
                onVolumeLevel?(rms)

                // 回呼音訊資料
                onAudioData?(pcmData)
            }
        } catch {
            // 偶發錯誤記錄（避免大量 log）
            errorCount += 1
            if errorCount % errorLogInterval == 0 {
                print("[AudioStreamOutput] Audio processing error (count: \(errorCount)): \(error)")
            }
        }
    }

    // MARK: - SCStreamDelegate

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[AudioStreamOutput] Stream stopped with error: \(error)")
        onError?(AudioCaptureError.streamFailed(error))
    }

    // MARK: - Private Methods: Audio Processing

    /// 複製音訊資料從 AudioBufferList 到 AVAudioPCMBuffer
    private func copyAudioData(
        from abl: UnsafeMutableAudioBufferListPointer,
        to buffer: AVAudioPCMBuffer
    ) {
        guard buffer.floatChannelData != nil else { return }

        let channelCount = min(Int(buffer.format.channelCount), abl.count)

        for channelIndex in 0..<channelCount {
            guard channelIndex < abl.count,
                  let targetChannelData = buffer.floatChannelData?[channelIndex],
                  let sourceData = abl[channelIndex].mData else {
                continue
            }

            let bytesToCopy = min(
                Int(abl[channelIndex].mDataByteSize),
                Int(buffer.frameCapacity) * MemoryLayout<Float>.size
            )
            memcpy(targetChannelData, sourceData, bytesToCopy)
        }
    }

    // MARK: - Private Methods: Converter (P3)

    /// 初始化音訊轉換器（含錯誤處理）
    private func initializeConverter(from desc: AudioStreamBasicDescription) {
        // 來源格式（系統預設，通常是 Float32 非交錯）
        guard let srcFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: desc.mSampleRate,
            channels: desc.mChannelsPerFrame,
            interleaved: false
        ) else {
            print("[AudioStreamOutput] Failed to create source format (rate: \(desc.mSampleRate), channels: \(desc.mChannelsPerFrame))")
            converterInitFailed = true
            return
        }

        // 目標格式：24kHz, Int16, 交錯（Deepgram 需要）
        // 使用源的聲道數（與 POC 一致）
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: targetSampleRate,
            channels: desc.mChannelsPerFrame,  // 使用源的聲道數
            interleaved: true
        ) else {
            print("[AudioStreamOutput] Failed to create target format")
            converterInitFailed = true
            return
        }

        // 建立轉換器
        guard let newConverter = AVAudioConverter(from: srcFormat, to: targetFormat) else {
            print("[AudioStreamOutput] Failed to create AVAudioConverter")
            converterInitFailed = true
            return
        }

        outputFormat = targetFormat
        converter = newConverter

        print("[AudioStreamOutput] Converter initialized: \(srcFormat.sampleRate)Hz/\(desc.mChannelsPerFrame)ch → \(targetSampleRate)Hz/\(desc.mChannelsPerFrame)ch")
    }

    /// 報告初始化失敗（只報告一次）
    private func reportInitFailureOnce() {
        guard !hasReportedInitFailure else { return }
        hasReportedInitFailure = true
        onError?(AudioCaptureError.converterInitFailed)
    }

    // MARK: - Private Methods: Analysis

    /// 計算 RMS 音量（用於判斷有無聲音）
    private func calculateRMS(_ data: Data) -> Float {
        let samples = data.withUnsafeBytes { buffer -> [Int16] in
            Array(buffer.bindMemory(to: Int16.self))
        }

        guard !samples.isEmpty else { return 0 }

        let sumOfSquares: Float = samples.reduce(0.0) { sum, sample in
            let normalized = Float(sample) / Float(Int16.max)
            return sum + (normalized * normalized)
        }

        return sqrt(sumOfSquares / Float(samples.count))
    }
}

// MARK: - ScreenStreamOutput

/// SCStreamOutput delegate（影像幀忽略用）
final class ScreenStreamOutput: NSObject, SCStreamOutput {
    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of outputType: SCStreamOutputType) {
        // 只要註冊 output 即可，影像幀直接忽略
        guard outputType == .screen else { return }
    }
}

// MARK: - AudioCaptureService

/// 音訊擷取服務
@MainActor
class AudioCaptureService: NSObject, ObservableObject {
    // MARK: - Properties

    /// 音訊格式：24kHz, 16-bit（聲道數由系統決定）
    let sampleRate: Double = 24_000
    let bytesPerSample: Int = 2

    /// 是否正在擷取
    @Published private(set) var isCapturing: Bool = false

    /// 目前音量（0.0 - 1.0）
    @Published var currentVolume: Float = 0

    /// 是否有音訊活動
    @Published var hasAudioActivity: Bool = false

    /// 最近的錯誤
    @Published var lastError: Error?

    /// 音訊資料回呼
    var onAudioData: ((Data) -> Void)?

    /// 錯誤回呼
    var onError: ((Error) -> Void)?

    // 私有屬性
    private var stream: SCStream?
    private var streamOutput: AudioStreamOutput?
    private var screenStreamOutput: ScreenStreamOutput?
    private var audioProcessingQueue: DispatchQueue?

    // 靜音檢測
    private let silenceThreshold: Float = 0.01
    private var silenceFrameCount: Int = 0
    private let silenceFramesRequired: Int = 10

    // MARK: - Public Methods

    /// 檢查是否有權限
    func hasPermission() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// 請求權限
    func requestPermission() -> Bool {
        return CGRequestScreenCaptureAccess()
    }

    /// 開始擷取
    func startCapture() async throws {
        // 清除之前的錯誤
        lastError = nil

        // 1. 檢查權限
        guard CGPreflightScreenCaptureAccess() else {
            // 嘗試請求權限
            CGRequestScreenCaptureAccess()
            throw AudioCaptureError.permissionDenied
        }

        // 2. 取得可分享內容
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let display = content.displays.first else {
            throw AudioCaptureError.noDisplay
        }

        // 3. 建立過濾器
        let filter = SCContentFilter(
            display: display,
            excludingApplications: [],
            exceptingWindows: []
        )

        // 4. 配置串流
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true  // 排除自身音訊避免迴授
        if #available(macOS 15.0, *) {
            config.captureMicrophone = false
        }

        // 5. 建立 stream output（P4: 包含 onError）
        streamOutput = AudioStreamOutput(
            onAudioData: { [weak self] data in
                self?.onAudioData?(data)
            },
            onVolumeLevel: { [weak self] rms in
                Task { @MainActor in
                    self?.updateVolumeLevel(rms)
                }
            },
            onError: { [weak self] error in
                Task { @MainActor in
                    self?.handleStreamError(error)
                }
            }
        )

        // 6. 建立串流
        stream = SCStream(filter: filter, configuration: config, delegate: streamOutput)

        guard let stream = stream, let streamOutput = streamOutput else {
            throw AudioCaptureError.streamFailed(NSError(domain: "AudioCapture", code: -1))
        }

        // 7. 添加音訊輸出（使用 .default QoS 避免 CPU 過載）
        audioProcessingQueue = DispatchQueue(label: "com.autosub.audio", qos: .default)
        do {
            try stream.addStreamOutput(
                streamOutput,
                type: .audio,
                sampleHandlerQueue: audioProcessingQueue!
            )
            // 註冊 screen output，避免系統丟棄影像幀時出錯
            screenStreamOutput = ScreenStreamOutput()
            try stream.addStreamOutput(
                screenStreamOutput!,
                type: .screen,
                sampleHandlerQueue: audioProcessingQueue!
            )
        } catch {
            audioProcessingQueue = nil
            throw AudioCaptureError.streamFailed(error)
        }

        // 8. 開始擷取
        do {
            try await stream.startCapture()
            isCapturing = true
        } catch {
            throw AudioCaptureError.streamFailed(error)
        }
    }

    /// 停止擷取
    func stopCapture() async {
        guard let stream = stream else { return }

        do {
            try await stream.stopCapture()
        } catch {
            print("[AudioCaptureService] Error stopping capture: \(error)")
        }

        self.stream = nil
        self.streamOutput = nil
        self.screenStreamOutput = nil
        self.audioProcessingQueue = nil
        isCapturing = false
        hasAudioActivity = false
        currentVolume = 0
    }

    // MARK: - Private Methods

    /// 更新音量等級並檢測靜音
    private func updateVolumeLevel(_ rms: Float) {
        currentVolume = rms

        if rms < silenceThreshold {
            silenceFrameCount += 1
            if silenceFrameCount >= silenceFramesRequired {
                hasAudioActivity = false
            }
        } else {
            silenceFrameCount = 0
            hasAudioActivity = true
        }
    }

    /// 處理串流錯誤（P4）
    private func handleStreamError(_ error: Error) {
        lastError = error
        onError?(error)
        print("[AudioCaptureService] Stream error: \(error.localizedDescription)")
    }
}

// MARK: - Debug Helpers

extension AudioCaptureService {
    /// 將音訊資料儲存到檔案（用於驗證格式）
    func saveAudioForVerification(_ data: Data, to filename: String) {
        guard let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return }

        let fileURL = documentsPath.appendingPathComponent(filename)
        do {
            try data.write(to: fileURL)
            print("[AudioCaptureService] Audio saved to: \(fileURL.path)")
            print("Verify with: ffprobe -i \(fileURL.path) -f s16le -ar 24000 -ac 2")
        } catch {
            print("[AudioCaptureService] Failed to save audio: \(error)")
        }
    }
}
