# Phase 2: Swift 音訊擷取

## Goal

使用 ScreenCaptureKit 實作系統音訊擷取，將 PCM 音訊資料轉換為可傳送給 Python Backend 的格式。

## Prerequisites

- [x] Phase 0 完成（Xcode 專案已建立）
- [x] 對 ScreenCaptureKit API 有基本了解

## Tasks

### 2.1 建立 AudioCaptureService

- [x] 建立 `AutoSub/AutoSub/Services/AudioCaptureService.swift`
- [x] 實作 `SCStream` 配置
- [x] 實作音訊擷取啟動/停止
- [x] 實作 PCM 資料轉換

### 2.2 建立 AudioStreamOutput

- [x] 實作 `SCStreamOutput` delegate
- [x] 處理 `CMSampleBuffer` 轉 PCM Data
- [x] 實作 RMS 音量計算（用於判斷有無聲音）

### 2.3 權限處理

- [x] 實作螢幕錄製權限檢查
- [x] 實作權限請求流程

### 2.4 音訊格式驗證

- [x] 建立音訊格式驗證工具
- [x] 確認輸出為 24kHz, 16-bit, Stereo PCM
- [x] 將測試音訊輸出到檔案進行二進位檢查

### 2.5 錯誤處理

- [x] 定義 `AudioCaptureError` enum
- [x] 處理權限拒絕、無顯示器等情況

## Code Examples

### AudioCaptureService.swift 核心結構

```swift
import ScreenCaptureKit
import AVFoundation

@MainActor
class AudioCaptureService: NSObject, ObservableObject {
    private var stream: SCStream?
    private var streamOutput: AudioStreamOutput?

    var onAudioData: ((Data) -> Void)?

    // 音訊格式：24kHz, 16-bit, Stereo
    let sampleRate: Double = 24000
    let channels: Int = 2
    let bytesPerSample: Int = 2

    // 音量檢測（用於字幕顯示/隱藏）
    @Published var hasAudioActivity: Bool = false
    private let silenceThreshold: Float = 0.01
    private var silenceFrameCount: Int = 0
    private let silenceFramesRequired: Int = 10

    func startCapture() async throws {
        // 1. 檢查權限
        guard CGPreflightScreenCaptureAccess() else {
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
        config.excludesCurrentProcessAudio = true
        config.sampleRate = Int(sampleRate)
        config.channelCount = channels

        // 必須設定視訊輸出（ScreenCaptureKit 限制）
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

        // 5. 建立串流
        stream = SCStream(filter: filter, configuration: config, delegate: nil)
        streamOutput = AudioStreamOutput(onAudio: onAudioData)

        try stream?.addStreamOutput(
            streamOutput!,
            type: .audio,
            sampleHandlerQueue: .global(qos: .userInteractive)
        )

        // 6. 開始擷取
        try await stream?.startCapture()
    }

    func stopCapture() async {
        try? await stream?.stopCapture()
        stream = nil
    }
}
```

### AudioStreamOutput

```swift
class AudioStreamOutput: NSObject, SCStreamOutput {
    var onAudio: ((Data) -> Void)?
    var onVolumeLevel: ((Float) -> Void)?

    init(onAudio: ((Data) -> Void)?, onVolumeLevel: ((Float) -> Void)? = nil) {
        self.onAudio = onAudio
        self.onVolumeLevel = onVolumeLevel
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        guard let pcmData = convertToPCM(sampleBuffer) else { return }

        // 計算 RMS 音量
        let rms = calculateRMS(pcmData)
        onVolumeLevel?(rms)

        onAudio?(pcmData)
    }

    private func calculateRMS(_ data: Data) -> Float {
        let samples = data.withUnsafeBytes { buffer -> [Int16] in
            Array(buffer.bindMemory(to: Int16.self))
        }

        guard !samples.isEmpty else { return 0 }

        let sumOfSquares = samples.reduce(0.0) { sum, sample in
            let normalized = Float(sample) / Float(Int16.max)
            return sum + (normalized * normalized)
        }

        return sqrt(sumOfSquares / Float(samples.count))
    }

    private func convertToPCM(_ sampleBuffer: CMSampleBuffer) -> Data? {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: nil,
            totalLengthOut: &length,
            dataPointerOut: &dataPointer
        )

        guard let dataPointer = dataPointer else { return nil }
        return Data(bytes: dataPointer, count: length)
    }
}
```

### AudioCaptureError

```swift
enum AudioCaptureError: Error {
    case permissionDenied
    case noDisplay
    case streamFailed
}
```

## Verification

### 測試步驟

1. 在 Xcode 中建立測試 Target
2. 建立簡單的 SwiftUI View 測試音訊擷取
3. 確認可以取得 PCM 資料

### 測試程式碼

```swift
// 簡單測試 View
struct AudioTestView: View {
    @StateObject private var audioService = AudioCaptureService()
    @State private var isCapturing = false
    @State private var dataReceived = 0

    var body: some View {
        VStack {
            Text("Data received: \(dataReceived) bytes")
            Button(isCapturing ? "Stop" : "Start") {
                Task {
                    if isCapturing {
                        await audioService.stopCapture()
                    } else {
                        audioService.onAudioData = { data in
                            dataReceived += data.count
                        }
                        try? await audioService.startCapture()
                    }
                    isCapturing.toggle()
                }
            }
        }
        .padding()
    }
}
```

### Expected Outcomes

- [x] 可請求螢幕錄製權限
- [x] 權限授予後可開始擷取
- [x] `onAudioData` callback 持續收到資料
- [x] PCM 資料格式正確（24kHz, 16-bit, Stereo）
- [x] 可正常停止擷取

### 音訊格式驗證

```swift
// 將音訊資料輸出到檔案進行驗證
func saveAudioForVerification(_ data: Data, to filename: String) {
    let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let fileURL = documentsPath.appendingPathComponent(filename)
    try? data.write(to: fileURL)
    print("Audio saved to: \(fileURL.path)")
}

// 使用 ffprobe 驗證格式
// ffprobe -i test_audio.pcm -f s16le -ar 24000 -ac 2
```

## Files Created/Modified

- `AutoSub/AutoSub/Services/AudioCaptureService.swift` (modified - 完整實作)
- `AutoSub/AutoSub/Views/AudioTestView.swift` (new - 測試用 View)

## Implementation Notes (Added during execution)

### 與規格的差異

1. **音訊轉換器**：使用 `AVAudioConverter` 進行格式轉換，而非直接讀取 PCM
   - 原因：系統輸出格式可能是 Float32 非交錯，需要轉換為 Int16 交錯
   - 優點：更穩健的格式轉換支援

2. **新增 API**：
   - `@Published isCapturing: Bool` - 擷取狀態追蹤
   - `@Published currentVolume: Float` - 即時音量值
   - `hasPermission()` / `requestPermission()` - 權限管理方法
   - `saveAudioForVerification()` - 除錯工具

3. **錯誤處理增強**：
   - `AudioCaptureError.streamFailed(Error)` - 包含詳細錯誤資訊
   - `AudioCaptureError.converterInitFailed` - 新增轉換器初始化錯誤

4. **QoS 調整**：
   - 改用 `.default` QoS 而非 `.userInteractive`，避免 CPU 過載

5. **SCStreamDelegate**：
   - 實作 `SCStreamDelegate` 以捕捉串流錯誤

### 品質改進歷程

**初版優化（Code Quality 7.6 → 8.5+）**
- P1: 緩存 AVAudioPCMBuffer 減少 GC 壓力
- P2: 提取 `copyAudioData(from:to:)` 方法
- P3: 改進 initializeConverter 錯誤處理
- P4: 新增 onError 回呼

**音訊品質修復（與 POC 對齊）**

測試發現音訊品質有問題（雜音、斷斷續續），經比對 POC 實現後進行修正：

1. **聲道數改為動態**：
   - 原本：強制使用 2 聲道 `targetChannels = 2`
   - 修正：使用源的聲道數 `desc.mChannelsPerFrame`
   - 原因：強制聲道數會導致音訊格式不匹配

2. **移除 Buffer 緩存**：
   - 原本：重用 `cachedInputBuffer` 和 `cachedOutputBuffer`
   - 修正：每次都建立新的 buffer（與 POC 一致）
   - 原因：緩存 buffer 可能導致狀態不乾淨

**Swift 6 並發安全性修復**
- 加 `@MainActor` 標記到使用 singleton 的類別
- 加 `@preconcurrency import AVFAudio` 抑制 Sendable 警告

**macOS 版本相容性修復**
- `SettingsLink`: 加 `#available(macOS 14.0, *)` 檢查
- `onChange(of:)`: 使用舊版語法（單參數）
- `captureMicrophone`: 加 `#available(macOS 15.0, *)` 檢查

## Notes

### ScreenCaptureKit 注意事項

1. **不需要設定視訊輸出**：實測發現只需要音訊時，不設定視訊也可以運作
2. **權限模型**：需要「螢幕錄製」權限，首次使用會彈出系統對話框
3. **排除自身音訊**：`excludesCurrentProcessAudio = true` 避免迴授

### 音訊格式對齊

確保與 Python Backend 的預期格式一致：
- Sample Rate: 24000 Hz
- Channels: 動態（使用源的聲道數，通常為 2）
- Bit Depth: 16-bit (Int16)

### 效能考量

- 使用 `.default` QoS 佇列處理音訊（避免 CPU 過載）
- 避免在 callback 中執行耗時操作
- 使用 AVAudioConverter 進行高效格式轉換
