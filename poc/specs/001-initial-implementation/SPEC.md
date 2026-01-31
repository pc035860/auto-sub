# Auto-Sub 技術規格書

## 1. 技術棧

| 類別 | 技術 | 版本 | 備註 |
|------|------|------|------|
| **Swift** | Swift | 6.0+ | Apple Silicon 優化 |
| **UI 框架** | SwiftUI | macOS 13+ | MenuBarExtra Scene |
| **音訊擷取** | ScreenCaptureKit | macOS 13+ | 系統音訊擷取 |
| **Python** | Python | ≥3.11 | 用戶環境 |
| **語音辨識** | Deepgram SDK | 5.3.2 | WebSocket 即時串流 |
| **翻譯** | Google GenAI SDK | 1.61.0 | gemini-2.5-flash-lite |
| **依賴管理** | uv | 最新 | 快速 Python 套件管理 |

---

## 2. 專案結構

```
AutoSub/
├── AutoSub.xcodeproj/
├── AutoSub/
│   ├── AutoSubApp.swift           # App 入口，MenuBarExtra
│   ├── Models/
│   │   ├── AppState.swift         # 應用程式狀態
│   │   ├── SubtitleEntry.swift    # 字幕資料模型
│   │   └── Configuration.swift    # 設定模型
│   ├── Views/
│   │   ├── MenuBarView.swift      # Menu Bar 下拉選單
│   │   ├── SettingsView.swift     # 設定視窗
│   │   ├── SubtitleOverlay.swift  # 字幕覆蓋層
│   │   └── OnboardingView.swift   # 首次使用引導
│   ├── Services/
│   │   ├── AudioCaptureService.swift    # ScreenCaptureKit 封裝
│   │   ├── PythonBridgeService.swift    # Python 子程序管理
│   │   └── ConfigurationService.swift   # 設定讀寫
│   ├── Utilities/
│   │   ├── SubtitleWindowController.swift  # NSWindow 管理
│   │   └── KeyboardShortcuts.swift         # 快捷鍵處理
│   └── Resources/
│       └── backend/                 # Python 後端（複製到 Bundle）
│           ├── main.py
│           ├── transcriber.py
│           ├── translator.py
│           └── requirements.txt
├── AutoSubTests/
└── README.md
```

---

## 3. 系統架構

### 3.1 整體流程

```
┌─────────────────────────────────────────────────────────────────────┐
│                        Swift App (AutoSub)                          │
│                                                                     │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────────────────┐ │
│  │ MenuBarView │    │ SettingsView│    │   SubtitleOverlay       │ │
│  └──────┬──────┘    └──────┬──────┘    └───────────┬─────────────┘ │
│         │                  │                       │                │
│         ▼                  ▼                       ▲                │
│  ┌─────────────────────────────────────────────────┴──────────────┐│
│  │                        AppState                                 ││
│  │  - isCapturing: Bool                                           ││
│  │  - currentSubtitle: SubtitleEntry?                             ││
│  │  - status: AppStatus (.idle, .capturing, .warning, .error)     ││
│  └─────────────────────────────────────────────────┬──────────────┘│
│                                                    │                │
│  ┌─────────────────────────┐    ┌─────────────────┴──────────────┐│
│  │  AudioCaptureService    │    │     PythonBridgeService        ││
│  │  (ScreenCaptureKit)     │───▶│     (Process + stdin/stdout)   ││
│  │                         │    │                                 ││
│  │  PCM Audio Data         │    │  ┌──────────────────────────┐  ││
│  │  24kHz, 16-bit, Stereo  │    │  │    Python Backend        │  ││
│  └─────────────────────────┘    │  │  ┌──────┐   ┌──────────┐ │  ││
│                                 │  │  │Deepgram│→│ Gemini  │ │  ││
│                                 │  │  │  STT  │   │翻譯     │ │  ││
│                                 │  │  └──────┘   └──────────┘ │  ││
│                                 │  └──────────────────────────┘  ││
│                                 └────────────────────────────────┘│
└─────────────────────────────────────────────────────────────────────┘
```

### 3.2 資料流

```
[系統音訊] ─PCM─▶ [Swift AudioCapture] ─stdin─▶ [Python Backend]
                                                      │
                                                      ▼
                                               [Deepgram STT]
                                                      │
                                                      ▼ 日文文字
                                               [Gemini 翻譯]
                                                      │
                                                      ▼ JSON
[字幕顯示] ◀─────────────────────────────────────stdout─┘
```

---

## 4. 模組規格

### 4.1 AppState（狀態管理）

```swift
import SwiftUI
import Combine

enum AppStatus {
    case idle           // 待機
    case capturing      // 擷取中
    case warning        // 警告（網路不穩等）
    case error          // 錯誤
}

@MainActor
class AppState: ObservableObject {
    @Published var status: AppStatus = .idle
    @Published var isCapturing: Bool = false
    @Published var currentSubtitle: SubtitleEntry?
    @Published var isConfigured: Bool = false

    // 設定
    @Published var deepgramApiKey: String = ""
    @Published var geminiApiKey: String = ""
    @Published var sourceLanguage: String = "ja"
    @Published var targetLanguage: String = "zh-TW"

    // 字幕設定
    @Published var subtitleFontSize: CGFloat = 24
    @Published var subtitleDisplayDuration: TimeInterval = 4.0
}
```

### 4.2 SubtitleEntry（字幕模型）

```swift
struct SubtitleEntry: Identifiable, Codable {
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
}
```

### 4.3 Python Backend JSON 協議

**Swift → Python (stdin)**：原始 PCM 音訊資料（二進位）

**Python → Swift (stdout)**：JSON Lines 格式

```json
{"type": "subtitle", "original": "こんにちは", "translation": "你好"}
{"type": "status", "status": "connected"}
{"type": "error", "message": "API connection failed", "code": "DEEPGRAM_ERROR"}
```

---

## 5. Swift 模組實作

### 5.1 AutoSubApp.swift（App 入口）

```swift
import SwiftUI

@main
struct AutoSubApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var audioService = AudioCaptureService()
    @StateObject private var pythonBridge = PythonBridgeService()

    var body: some Scene {
        // Menu Bar App
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            Image(systemName: menuBarIcon)
                .foregroundColor(menuBarColor)
        }

        // 設定視窗
        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        // 字幕覆蓋層（獨立視窗）
        Window("Subtitle", id: "subtitle") {
            SubtitleOverlay()
                .environmentObject(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    private var menuBarIcon: String {
        switch appState.status {
        case .idle: return "captions.bubble"
        case .capturing: return "captions.bubble.fill"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    private var menuBarColor: Color {
        switch appState.status {
        case .idle: return .primary
        case .capturing: return .green
        case .warning: return .yellow
        case .error: return .red
        }
    }
}
```

### 5.2 AudioCaptureService.swift

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
    private let silenceThreshold: Float = 0.01  // RMS 閾值
    private var silenceFrameCount: Int = 0
    private let silenceFramesRequired: Int = 10  // 連續 10 個 chunk 無聲視為靜音

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

        // 3. 建立過濾器（擷取整個顯示器）
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

        // 注意：必須設定視訊輸出（ScreenCaptureKit 限制）
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)  // 1 FPS 最小化

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

// 音訊輸出處理
class AudioStreamOutput: NSObject, SCStreamOutput {
    var onAudio: ((Data) -> Void)?
    var onVolumeLevel: ((Float) -> Void)?  // 音量回呼

    init(onAudio: ((Data) -> Void)?, onVolumeLevel: ((Float) -> Void)? = nil) {
        self.onAudio = onAudio
        self.onVolumeLevel = onVolumeLevel
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }

        // 轉換為 PCM 資料
        guard let pcmData = convertToPCM(sampleBuffer) else { return }

        // 計算 RMS 音量（用於判斷是否有聲音）
        let rms = calculateRMS(pcmData)
        onVolumeLevel?(rms)

        onAudio?(pcmData)
    }

    /// 計算 RMS（均方根）音量
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

enum AudioCaptureError: Error {
    case permissionDenied
    case noDisplay
    case streamFailed
}
```

### 5.3 PythonBridgeService.swift

```swift
import Foundation

@MainActor
class PythonBridgeService: ObservableObject {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?

    var onSubtitle: ((SubtitleEntry) -> Void)?
    var onError: ((String) -> Void)?

    private let backendPath: URL
    private let venvPath: URL

    init() {
        // 後端位於 App Bundle
        let resourcePath = Bundle.main.resourceURL!
        backendPath = resourcePath.appendingPathComponent("backend")

        // venv 位於 Application Support
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        venvPath = appSupport.appendingPathComponent("AutoSub/.venv")
    }

    func start(config: Configuration) async throws {
        // 1. 確保 venv 存在
        if !FileManager.default.fileExists(atPath: venvPath.path) {
            try await setupVenv()
        }

        // 2. 啟動 Python 程序
        process = Process()
        stdinPipe = Pipe()
        stdoutPipe = Pipe()

        let pythonPath = venvPath.appendingPathComponent("bin/python3")
        let mainPyPath = backendPath.appendingPathComponent("main.py")

        process?.executableURL = pythonPath
        process?.arguments = [mainPyPath.path]
        process?.currentDirectoryURL = backendPath

        // 環境變數
        var env = ProcessInfo.processInfo.environment
        env["DEEPGRAM_API_KEY"] = config.deepgramApiKey
        env["GEMINI_API_KEY"] = config.geminiApiKey
        env["SOURCE_LANGUAGE"] = config.sourceLanguage
        env["TARGET_LANGUAGE"] = config.targetLanguage
        process?.environment = env

        process?.standardInput = stdinPipe
        process?.standardOutput = stdoutPipe

        // 監聽 stdout
        stdoutPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleOutput(data)
        }

        try process?.run()
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    func sendAudio(_ data: Data) {
        stdinPipe?.fileHandleForWriting.write(data)
    }

    private func handleOutput(_ data: Data) {
        guard let line = String(data: data, encoding: .utf8) else { return }

        // JSON Lines 格式
        for jsonLine in line.components(separatedBy: "\n") where !jsonLine.isEmpty {
            guard let jsonData = jsonLine.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let type = json["type"] as? String else {
                continue
            }

            DispatchQueue.main.async { [weak self] in
                switch type {
                case "subtitle":
                    if let original = json["original"] as? String,
                       let translation = json["translation"] as? String {
                        let entry = SubtitleEntry(original: original, translated: translation)
                        self?.onSubtitle?(entry)
                    }
                case "error":
                    if let message = json["message"] as? String {
                        self?.onError?(message)
                    }
                default:
                    break
                }
            }
        }
    }

    private func setupVenv() async throws {
        // 建立 venv 並安裝依賴
        let venvProcess = Process()
        venvProcess.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        venvProcess.arguments = ["-m", "venv", venvPath.path]
        try venvProcess.run()
        venvProcess.waitUntilExit()

        // pip install
        let pipProcess = Process()
        pipProcess.executableURL = venvPath.appendingPathComponent("bin/pip")
        pipProcess.arguments = ["install", "-r", backendPath.appendingPathComponent("requirements.txt").path]
        try pipProcess.run()
        pipProcess.waitUntilExit()
    }
}
```

### 5.4 SubtitleOverlay.swift（字幕視圖）

```swift
import SwiftUI

struct SubtitleOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var isVisible: Bool = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 4) {
            if let subtitle = appState.currentSubtitle, isVisible {
                // 原文（日文）
                Text(subtitle.originalText)
                    .font(.system(size: appState.subtitleFontSize * 0.85))
                    .foregroundColor(.white.opacity(0.8))

                // 翻譯（中文）
                Text(subtitle.translatedText)
                    .font(.system(size: appState.subtitleFontSize))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .onChange(of: appState.currentSubtitle) { newSubtitle in
            if newSubtitle != nil {
                showSubtitle()
            }
        }
    }

    private func showSubtitle() {
        // 取消之前的隱藏計時器
        hideTask?.cancel()

        // 顯示字幕
        withAnimation {
            isVisible = true
        }

        // 設定自動隱藏計時器（預設 4 秒）
        hideTask = Task {
            try? await Task.sleep(for: .seconds(appState.subtitleDisplayDuration))
            if !Task.isCancelled {
                await MainActor.run {
                    withAnimation {
                        isVisible = false
                    }
                }
            }
        }
    }
}
```

### 5.5 SubtitleWindowController.swift（視窗管理）

```swift
import AppKit
import SwiftUI

class SubtitleWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    func show<Content: View>(content: Content) {
        if window == nil {
            createWindow()
        }

        hostingView?.rootView = AnyView(content)
        window?.orderFront(nil)
    }

    func hide() {
        window?.orderOut(nil)
    }

    private func createWindow() {
        // 取得螢幕尺寸
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // 字幕位置：螢幕底部，寬度 80%
        let width = screenFrame.width * 0.8
        let height: CGFloat = 120
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + 50  // 距離底部 50pt

        let frame = NSRect(x: x, y: y, width: width, height: height)

        // 建立透明無邊框視窗
        window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = false
        window?.level = .statusBar + 1  // 置頂
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window?.ignoresMouseEvents = true  // 點擊穿透

        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        window?.contentView = hostingView
    }
}
```

---

## 6. Python Backend 規格

### 6.1 main.py

```python
#!/usr/bin/env python3
"""
Auto-Sub Python Backend
從 stdin 讀取 PCM 音訊，輸出翻譯後的字幕到 stdout
"""

import sys
import os
import json
import asyncio
from transcriber import Transcriber
from translator import Translator

# 確保即時輸出
sys.stdout.reconfigure(line_buffering=True)

# 音訊格式常數
SAMPLE_RATE = 24000
CHANNELS = 2
BYTES_PER_SAMPLE = 2
CHUNK_DURATION_MS = 100
CHUNK_SIZE = SAMPLE_RATE * CHANNELS * BYTES_PER_SAMPLE * CHUNK_DURATION_MS // 1000


def output_json(data: dict):
    """輸出 JSON 到 stdout"""
    print(json.dumps(data, ensure_ascii=False), flush=True)


async def main():
    # 從環境變數讀取設定
    deepgram_key = os.environ.get("DEEPGRAM_API_KEY")
    gemini_key = os.environ.get("GEMINI_API_KEY")
    source_lang = os.environ.get("SOURCE_LANGUAGE", "ja")

    if not deepgram_key or not gemini_key:
        output_json({"type": "error", "message": "Missing API keys", "code": "CONFIG_ERROR"})
        sys.exit(1)

    # 初始化翻譯器
    translator = Translator(api_key=gemini_key)

    # 翻譯回呼（含重試）
    async def on_transcript(text: str):
        max_retries = 3
        for attempt in range(max_retries):
            try:
                translated = translator.translate(text)
                if translated:
                    output_json({
                        "type": "subtitle",
                        "original": text,
                        "translation": translated
                    })
                    return
            except Exception as e:
                if attempt == max_retries - 1:
                    output_json({
                        "type": "error",
                        "message": f"Translation failed: {str(e)}",
                        "code": "TRANSLATE_ERROR"
                    })

    # 初始化轉錄器
    async with Transcriber(
        api_key=deepgram_key,
        language=source_lang,
        on_transcript=on_transcript
    ) as transcriber:
        output_json({"type": "status", "status": "connected"})

        # 從 stdin 讀取音訊
        while True:
            try:
                audio_data = sys.stdin.buffer.read(CHUNK_SIZE)
                if not audio_data:
                    break
                await transcriber.send_audio(audio_data)
            except Exception as e:
                output_json({
                    "type": "error",
                    "message": str(e),
                    "code": "AUDIO_ERROR"
                })
                break


if __name__ == "__main__":
    asyncio.run(main())
```

### 6.2 transcriber.py

```python
"""
Deepgram 即時語音轉文字模組
使用 Deepgram SDK v5.3.2
"""

import sys
import asyncio
from typing import Callable, Optional
from deepgram import (
    DeepgramClient,
    DeepgramClientOptions,
    LiveTranscriptionEvents,
    LiveOptions,
)


class Transcriber:
    def __init__(
        self,
        api_key: str,
        language: str = "ja",
        on_transcript: Optional[Callable[[str], None]] = None,
        endpointing_ms: int = 300,
    ):
        self.api_key = api_key
        self.language = language
        self.on_transcript = on_transcript
        self.endpointing_ms = endpointing_ms

        self.client: Optional[DeepgramClient] = None
        self.connection = None

    async def __aenter__(self):
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.disconnect()

    async def connect(self):
        # 建立客戶端（啟用 keepalive）
        config = DeepgramClientOptions(options={"keepalive": "true"})
        self.client = DeepgramClient(self.api_key, config)

        # 建立 WebSocket 連線
        self.connection = self.client.listen.asyncwebsocket.v("1")

        # 註冊事件處理
        self.connection.on(LiveTranscriptionEvents.Transcript, self._on_message)
        self.connection.on(LiveTranscriptionEvents.Error, self._on_error)

        # 連線選項
        options = LiveOptions(
            model="nova-2",
            language=self.language,
            smart_format=True,
            interim_results=True,
            endpointing=self.endpointing_ms,
            encoding="linear16",
            sample_rate=24000,
            channels=2,
        )

        await self.connection.start(options)

    async def disconnect(self):
        if self.connection:
            await self.connection.finish()

    async def send_audio(self, audio_data: bytes):
        if self.connection:
            await self.connection.send(audio_data)

    def _on_message(self, *args, **kwargs):
        result = kwargs.get("result")
        if not result:
            return

        # 只處理最終結果
        if not result.is_final:
            return

        transcript = result.channel.alternatives[0].transcript
        if transcript and self.on_transcript:
            asyncio.create_task(self.on_transcript(transcript))

    def _on_error(self, *args, **kwargs):
        error = kwargs.get("error")
        print(f"Deepgram error: {error}", file=sys.stderr)
```

### 6.3 translator.py

```python
"""
Gemini 翻譯模組
使用 Google GenAI SDK 1.61.0
"""

from google import genai


TRANSLATION_PROMPT = """你是專業的日文翻譯。請將以下日文翻譯成繁體中文。

規則：
- 保持原意，語句通順自然
- 人名保留日文發音的中文音譯
- 作品名、專有名詞使用台灣常見譯法
- 只輸出翻譯結果，不要加任何解釋

日文原文：
{text}
"""


class Translator:
    def __init__(self, api_key: str, model: str = "gemini-2.5-flash-lite"):
        self.client = genai.Client(api_key=api_key)
        self.model = model

    def translate(self, text: str) -> str:
        """翻譯日文到繁體中文"""
        if not text.strip():
            return ""

        response = self.client.models.generate_content(
            model=self.model,
            contents=TRANSLATION_PROMPT.format(text=text),
        )

        return response.text.strip()
```

### 6.4 requirements.txt

```
deepgram-sdk>=5.3.2
google-genai>=1.61.0
python-dotenv>=1.2.1
```

---

## 7. 設定儲存

### 7.1 Configuration 模型

```swift
struct Configuration: Codable {
    var deepgramApiKey: String
    var geminiApiKey: String
    var sourceLanguage: String = "ja"
    var targetLanguage: String = "zh-TW"
    var subtitleFontSize: CGFloat = 24
    var subtitleDisplayDuration: TimeInterval = 4.0
    var showOriginalText: Bool = true  // 雙語顯示
}
```

### 7.2 儲存位置

```
~/Library/Application Support/AutoSub/
├── config.json          # 設定檔（加密儲存 API Keys）
├── .venv/               # Python 虛擬環境
└── logs/                # 執行日誌
```

### 7.3 API Key 安全儲存

```swift
import Security

class KeychainService {
    static func save(key: String, value: String) throws {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }
}
```

---

## 8. 快捷鍵

| 動作 | 預設快捷鍵 | 實作方式 |
|------|-----------|---------|
| 開始/停止 | ⌘ + Shift + S | NSEvent.addGlobalMonitorForEvents |
| 隱藏字幕 | ⌘ + Shift + H | NSEvent.addGlobalMonitorForEvents |

```swift
import Carbon

class KeyboardShortcuts {
    static func register() {
        // 註冊全域快捷鍵
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // ⌘ + Shift + S
            if flags == [.command, .shift] && event.keyCode == 1 {  // 's'
                NotificationCenter.default.post(name: .toggleCapture, object: nil)
            }

            // ⌘ + Shift + H
            if flags == [.command, .shift] && event.keyCode == 4 {  // 'h'
                NotificationCenter.default.post(name: .toggleSubtitle, object: nil)
            }
        }
    }
}

extension Notification.Name {
    static let toggleCapture = Notification.Name("toggleCapture")
    static let toggleSubtitle = Notification.Name("toggleSubtitle")
}
```

---

## 9. 錯誤處理

### 9.1 錯誤類型

```swift
enum AutoSubError: Error, LocalizedError {
    case pythonNotFound
    case venvSetupFailed
    case apiKeyMissing
    case permissionDenied
    case connectionFailed
    case translationFailed

    var errorDescription: String? {
        switch self {
        case .pythonNotFound: return "找不到 Python 3.11+，請先安裝"
        case .venvSetupFailed: return "Python 環境設定失敗"
        case .apiKeyMissing: return "請先設定 API Keys"
        case .permissionDenied: return "請授權螢幕錄製權限"
        case .connectionFailed: return "無法連接到語音服務"
        case .translationFailed: return "翻譯服務暫時不可用"
        }
    }
}
```

### 9.2 重試策略

| 錯誤類型 | 重試次數 | 間隔 |
|---------|---------|------|
| 翻譯失敗 | 3 次 | 無間隔 |
| 連線中斷 | 5 次 | 指數退避（1s, 2s, 4s...） |
| API 限流 | 3 次 | 固定 5 秒 |

---

## 10. 安全性考量

### 10.1 API Key 保護

| 層級 | 措施 | 說明 |
|------|------|------|
| 儲存 | Keychain | 使用 macOS Keychain 加密儲存，不明文存檔 |
| 傳遞 | 環境變數 | 透過 Process.environment 傳給 Python |
| config.json | 不含敏感資料 | 只儲存語言設定、字幕樣式等 |

### 10.2 網路安全

| 服務 | 協議 | 驗證 |
|------|------|------|
| Deepgram | WSS (WebSocket Secure) | API Key Header |
| Gemini | HTTPS | API Key |

### 10.3 錯誤訊息規範

為避免敏感資訊洩露，Python Backend 的錯誤輸出應：

```python
# ❌ 不安全：可能包含 API Key 或內部路徑
output_json({"type": "error", "message": str(exception)})

# ✅ 安全：只輸出代碼和使用者友善訊息
output_json({
    "type": "error",
    "code": "DEEPGRAM_ERROR",
    "message": "語音辨識服務暫時不可用"
})
```

### 10.4 應用程式簽名（獨立發布）

由於不上 App Store，需要：

1. **Developer ID 簽名**：使用 Apple Developer ID 簽署 App
2. **Notarization**：提交 Apple 公證，避免被 Gatekeeper 阻擋
3. **Hardened Runtime**：啟用強化執行環境

```bash
# 簽名指令
codesign --deep --force --verify --verbose \
    --sign "Developer ID Application: Your Name (TEAM_ID)" \
    --options runtime \
    AutoSub.app

# 公證
xcrun notarytool submit AutoSub.zip \
    --apple-id "your@email.com" \
    --team-id "TEAM_ID" \
    --wait
```

---

## 11. 效能目標

| 指標 | 目標值 | 量測方式 |
|------|--------|---------|
| 總延遲 | < 2 秒 | 從說話到字幕顯示 |
| CPU（擷取中） | < 10% | Activity Monitor |
| CPU（閒置） | < 1% | Activity Monitor |
| 記憶體 | < 100MB | Activity Monitor |
| 長時間運行 | > 4 小時無崩潰 | 實際測試 |

---

## 12. 部署

### 11.1 App Bundle 結構

```
AutoSub.app/
└── Contents/
    ├── MacOS/
    │   └── AutoSub              # Swift 主程式
    ├── Resources/
    │   └── backend/
    │       ├── main.py
    │       ├── transcriber.py
    │       ├── translator.py
    │       └── requirements.txt
    ├── Info.plist
    └── Entitlements.plist
```

### 11.2 Info.plist 關鍵設定

```xml
<key>LSUIElement</key>
<true/>  <!-- 隱藏 Dock 圖示 -->

<key>LSMinimumSystemVersion</key>
<string>13.0</string>

<key>NSScreenCaptureUsageDescription</key>
<string>Auto-Sub 需要存取螢幕錄製權限以擷取系統音訊</string>
```

### 11.3 Entitlements

```xml
<key>com.apple.security.app-sandbox</key>
<false/>  <!-- 不使用 Sandbox（需要執行外部 Python）-->

<key>com.apple.security.automation.apple-events</key>
<true/>
```

---

## 13. 測試計劃

### 12.1 單元測試

| 模組 | 測試項目 |
|------|---------|
| Configuration | 讀寫、Keychain 儲存 |
| SubtitleEntry | JSON 序列化 |
| Translator | 翻譯正確性 |

### 12.2 整合測試

| 場景 | 預期結果 |
|------|---------|
| 首次啟動 | 顯示引導畫面 |
| 無 Python | 顯示安裝提示 |
| API Key 錯誤 | 顯示錯誤訊息 |
| 網路中斷 | Menu Bar 變黃，嘗試重連 |
| 長時間運行 | 4 小時無崩潰 |

---

## 14. 參考資源

- [ScreenCaptureKit 文件](https://developer.apple.com/documentation/screencapturekit)
- [Deepgram Python SDK](https://developers.deepgram.com/docs/python-sdk)
- [Google GenAI SDK](https://googleapis.github.io/python-genai/)
- [SwiftUI MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)
