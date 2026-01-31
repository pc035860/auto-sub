# Phase 3: Swift-Python 橋接

## Goal

建立 Swift 與 Python Backend 之間的通訊機制，透過 stdin/stdout 進行 IPC（進程間通訊）。

## Prerequisites

- [ ] Phase 1 完成（Python Backend 已就緒）
- [ ] Phase 2 完成（AudioCaptureService 可輸出 PCM）

## Tasks

### 3.1 建立 PythonBridgeService

- [ ] 建立 `AutoSub/AutoSub/Services/PythonBridgeService.swift`
- [ ] 實作 Python 子程序啟動
- [ ] 實作 stdin 寫入（音訊資料）
- [ ] 實作 stdout 讀取（JSON 解析）

### 3.2 建立 Configuration 模型

- [ ] 建立 `AutoSub/AutoSub/Models/Configuration.swift`
- [ ] 定義 API Keys 和設定項目

### 3.3 建立 SubtitleEntry 模型

- [ ] 建立 `AutoSub/AutoSub/Models/SubtitleEntry.swift`
- [ ] 定義字幕資料結構

### 3.4 實作 venv 自動設置

- [ ] 實作首次執行時自動建立 venv
- [ ] 實作 pip install requirements

### 3.5 錯誤處理

- [ ] 解析 Python 輸出的 error JSON
- [ ] 傳遞錯誤給 UI 層

## Code Examples

### PythonBridgeService.swift

```swift
import Foundation

@MainActor
class PythonBridgeService: ObservableObject {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?

    var onSubtitle: ((SubtitleEntry) -> Void)?
    var onError: ((String) -> Void)?
    var onStatusChange: ((String) -> Void)?

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

    private var outputBuffer = ""  // 處理 JSON Lines 緩衝邊界

    private func handleOutput(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }

        // 處理緩衝邊界：stdout 可能在 JSON 行中間斷開
        outputBuffer += text

        // JSON Lines 格式：只處理完整的行
        while let newlineIndex = outputBuffer.firstIndex(of: "\n") {
            let jsonLine = String(outputBuffer[..<newlineIndex])
            outputBuffer = String(outputBuffer[outputBuffer.index(after: newlineIndex)...])

            guard !jsonLine.isEmpty else { continue }
            guard let jsonData = jsonLine.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let type = json["type"] as? String else {
                // 如果解析失敗，記錄但不中斷
                print("Failed to parse JSON: \(jsonLine)")
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
                case "status":
                    if let status = json["status"] as? String {
                        self?.onStatusChange?(status)
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
        // 確保目錄存在
        let appSupportDir = venvPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: appSupportDir, withIntermediateDirectories: true)

        // 建立 venv
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

### Configuration.swift

```swift
struct Configuration: Codable {
    var deepgramApiKey: String
    var geminiApiKey: String
    var sourceLanguage: String = "ja"
    var targetLanguage: String = "zh-TW"
    var subtitleFontSize: CGFloat = 24
    var subtitleDisplayDuration: TimeInterval = 4.0
    var showOriginalText: Bool = true
}
```

### SubtitleEntry.swift

```swift
struct SubtitleEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let originalText: String
    let translatedText: String
    let timestamp: Date

    init(original: String, translated: String) {
        self.id = UUID()
        self.originalText = original
        self.translatedText = translated
        self.timestamp = Date()
    }
}
```

## Verification

### 測試步驟

1. 確保 Python Backend 已就緒（Phase 1）
2. 在 Xcode 中測試 PythonBridgeService
3. 發送測試音訊資料
4. 確認收到 JSON 回應

### 整合測試程式碼

```swift
// 整合測試
func testBridge() async {
    let bridge = PythonBridgeService()
    let config = Configuration(
        deepgramApiKey: "test-key",
        geminiApiKey: "test-key"
    )

    bridge.onSubtitle = { subtitle in
        print("Received: \(subtitle.originalText) → \(subtitle.translatedText)")
    }

    bridge.onError = { error in
        print("Error: \(error)")
    }

    do {
        try await bridge.start(config: config)
        // 發送測試資料...
    } catch {
        print("Failed to start: \(error)")
    }
}
```

### Expected Outcomes

- [ ] 可成功啟動 Python 子程序
- [ ] venv 自動建立並安裝依賴
- [ ] stdin 可寫入二進位資料
- [ ] stdout JSON 正確解析
- [ ] `onSubtitle` callback 收到字幕
- [ ] `onError` callback 收到錯誤
- [ ] 可正常終止 Python 程序

## Files Created/Modified

- `AutoSub/AutoSub/Services/PythonBridgeService.swift` (new)
- `AutoSub/AutoSub/Models/Configuration.swift` (new)
- `AutoSub/AutoSub/Models/SubtitleEntry.swift` (new)

## Notes

### Process 生命週期

- 使用 `terminate()` 結束 Python 程序
- 需要處理程序異常結束的情況
- 考慮加入 heartbeat 機制檢測程序存活

### venv 路徑

```
~/Library/Application Support/AutoSub/
├── .venv/               # Python 虛擬環境
├── config.json          # 設定檔
└── logs/                # 執行日誌
```

### Thread Safety

- `handleOutput` 在背景執行緒被呼叫
- 使用 `DispatchQueue.main.async` 回到主執行緒
- 避免在 callback 中直接修改 UI 狀態

### 效能考量

- stdin 寫入應該是非阻塞的
- 大量音訊資料時考慮批次寫入
- stdout 讀取使用 `readabilityHandler` 是非阻塞的
