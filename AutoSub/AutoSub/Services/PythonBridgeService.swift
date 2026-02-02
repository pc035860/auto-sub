//
//  PythonBridgeService.swift
//  AutoSub
//
//  Python 子程序管理服務
//  Phase 3 實作：Swift ↔ Python IPC（stdin/stdout）
//

import Foundation

// MARK: - Error Types

/// Python Bridge 錯誤類型
enum PythonBridgeError: Error, LocalizedError {
    case bundleResourceNotFound
    case appSupportNotFound
    case pythonNotFound
    case venvSetupFailed(String)
    case dependencyInstallFailed(String)
    case processStartFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundleResourceNotFound:
            return "找不到 App Bundle 資源目錄"
        case .appSupportNotFound:
            return "找不到 Application Support 目錄"
        case .pythonNotFound:
            return "找不到 Python 3，請先安裝"
        case .venvSetupFailed(let detail):
            return "Python 虛擬環境建立失敗: \(detail)"
        case .dependencyInstallFailed(let detail):
            return "依賴安裝失敗: \(detail)"
        case .processStartFailed(let detail):
            return "Python 程序啟動失敗: \(detail)"
        }
    }
}

// MARK: - Output Buffer Handler

/// JSON Lines 輸出緩衝處理器（Thread-safe，獨立於 MainActor）
/// 用於處理 readabilityHandler 在背景執行緒的呼叫
private final class OutputBufferHandler: @unchecked Sendable {
    private var buffer = ""
    private let lock = NSLock()

    /// 處理新收到的資料，返回已完成的 JSON 行
    func processData(_ data: Data) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        lock.lock()
        defer { lock.unlock() }

        buffer += text

        // JSON Lines 格式：只處理完整的行
        var completedLines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: "\n") {
            let jsonLine = String(buffer[..<newlineIndex])
            buffer = String(buffer[buffer.index(after: newlineIndex)...])
            if !jsonLine.isEmpty {
                completedLines.append(jsonLine)
            }
        }

        return completedLines
    }

    /// 清空緩衝
    func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer = ""
    }
}

// MARK: - PythonBridgeService

/// Python Bridge 服務
/// 管理 Python 子程序生命週期、stdin/stdout IPC 通訊
@MainActor
class PythonBridgeService: ObservableObject {
    // MARK: - Properties

    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    /// 收到原文時的回呼（id, text）- 用於顯示「翻譯中」狀態
    var onTranscript: ((UUID, String) -> Void)?

    /// 字幕回呼（翻譯完成）
    var onSubtitle: ((SubtitleEntry) -> Void)?

    /// Interim 回呼（text）- 正在說的話
    var onInterim: ((String) -> Void)?

    /// 錯誤回呼
    var onError: ((String) -> Void)?

    /// 狀態變更回呼
    var onStatusChange: ((String) -> Void)?

    /// Python Backend 路徑（App Bundle 內）
    private let backendPath: URL

    /// venv 路徑（Application Support）
    private let venvPath: URL

    /// 輸出緩衝處理器（Thread-safe）
    private let outputHandler = OutputBufferHandler()

    /// 是否正在運行
    @Published private(set) var isRunning = false

    // MARK: - Initialization

    /// 初始化 Python Bridge 服務
    /// - Throws: PythonBridgeError 如果無法找到必要路徑
    init() throws {
        // 後端位於 App Bundle（安全解包）
        guard let resourcePath = Bundle.main.resourceURL else {
            throw PythonBridgeError.bundleResourceNotFound
        }
        backendPath = resourcePath.appendingPathComponent("backend")

        // venv 位於 Application Support（使用拋出式 API，自動建立目錄）
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        venvPath = appSupport.appendingPathComponent("AutoSub/.venv")
    }

    // MARK: - Public Methods

    /// 啟動 Python Backend
    /// - Parameter config: 應用程式設定（包含 API Keys）
    func start(config: Configuration) async throws {
        // 防止重複啟動
        guard !isRunning else {
            print("[PythonBridge] Already running")
            return
        }

        // 1. 確保 venv 存在
        if !FileManager.default.fileExists(atPath: venvPath.path) {
            print("[PythonBridge] Setting up venv...")
            try await setupVenv()
            print("[PythonBridge] venv setup complete")
        }

        // 2. 準備管道
        process = Process()
        stdinPipe = Pipe()
        stdoutPipe = Pipe()
        stderrPipe = Pipe()

        // 3. 設定執行路徑
        let pythonPath = venvPath.appendingPathComponent("bin/python3")
        let mainPyPath = backendPath.appendingPathComponent("main.py")

        // 檢查 Python 是否存在
        guard FileManager.default.fileExists(atPath: pythonPath.path) else {
            throw PythonBridgeError.pythonNotFound
        }

        process?.executableURL = pythonPath
        process?.arguments = [mainPyPath.path]
        process?.currentDirectoryURL = backendPath

        // 4. 設定環境變數（傳遞 API Keys）
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"  // 防止 stdout 緩衝導致阻塞
        env["DEEPGRAM_API_KEY"] = config.deepgramApiKey
        env["GEMINI_API_KEY"] = config.geminiApiKey
        env["SOURCE_LANGUAGE"] = config.sourceLanguage
        env["TARGET_LANGUAGE"] = config.targetLanguage
        process?.environment = env

        // 5. 連接管道
        process?.standardInput = stdinPipe
        process?.standardOutput = stdoutPipe
        process?.standardError = stderrPipe

        // 6. 監聽 stdout（處理 EOF）
        // 注意：readabilityHandler 在背景執行緒被呼叫
        // 使用 outputHandler（@unchecked Sendable）處理緩衝
        let handler = outputHandler
        stdoutPipe?.fileHandleForReading.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty {
                // EOF：清理 handler
                fileHandle.readabilityHandler = nil
                return
            }

            // 在背景執行緒處理緩衝
            let completedLines = handler.processData(data)

            // 解析並分發到主線程
            for jsonLine in completedLines {
                self?.parseAndDispatch(jsonLine)
            }
        }

        // 7. 監聽 stderr（用於調試）
        stderrPipe?.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            if data.isEmpty {
                fileHandle.readabilityHandler = nil
                return
            }
            if let text = String(data: data, encoding: .utf8) {
                print("[Python stderr] \(text)")
            }
        }

        // 8. 啟動程序
        do {
            try process?.run()
            isRunning = true
            print("[PythonBridge] Python process started")
        } catch {
            throw PythonBridgeError.processStartFailed(error.localizedDescription)
        }
    }

    /// 停止 Python Backend
    func stop() {
        guard isRunning else { return }

        // 清理 handlers（避免資源洩漏）
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        // 關閉 stdin（通知 Python 正常結束）
        try? stdinPipe?.fileHandleForWriting.close()

        // 終止程序
        process?.terminate()

        // 清理資源
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
        outputHandler.clear()
        isRunning = false

        print("[PythonBridge] Python process stopped")
    }

    /// 發送音訊資料到 Python Backend
    /// - Parameter data: PCM 音訊資料（24kHz, 16-bit, stereo）
    func sendAudio(_ data: Data) {
        guard isRunning else { return }

        // 安全寫入（處理管道關閉情況）
        do {
            try stdinPipe?.fileHandleForWriting.write(contentsOf: data)
        } catch {
            print("[PythonBridge] Write error: \(error)")
        }
    }

    // MARK: - Private Methods

    /// 解析 JSON 並分發到對應的回呼
    /// 注意：這個方法從背景執行緒被呼叫（透過 readabilityHandler）
    /// 使用 nonisolated 標記，因為這是在 Sendable closure 中被呼叫
    private nonisolated func parseAndDispatch(_ jsonLine: String) {
        print("[PythonBridge] Received JSON line: \(jsonLine)")

        guard let jsonData = jsonLine.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let type = json["type"] as? String else {
            print("[PythonBridge] Failed to parse JSON: \(jsonLine)")
            return
        }

        print("[PythonBridge] Parsed type: \(type)")

        // 回到主線程處理 UI 更新（使用 Task @MainActor）
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            switch type {
            case "transcript":
                // 新增：處理原文（翻譯中狀態）
                if let idString = json["id"] as? String,
                   let id = UUID(uuidString: idString),
                   let text = json["text"] as? String {
                    print("[PythonBridge] Transcript received - id: \(idString), text: \(text)")
                    self.onTranscript?(id, text)
                }

            case "interim":
                // 處理 interim（正在說的話）
                if let text = json["text"] as? String {
                    print("[PythonBridge] Interim received: \(text)")
                    self.onInterim?(text)
                }

            case "subtitle":
                // 修改：包含 id，用於更新對應的 transcript
                if let idString = json["id"] as? String,
                   let id = UUID(uuidString: idString),
                   let original = json["original"] as? String,
                   let translation = json["translation"] as? String {
                    print("[PythonBridge] Subtitle received - id: \(idString), original: \(original), translation: \(translation)")
                    let entry = SubtitleEntry(
                        id: id,
                        originalText: original,
                        translatedText: translation
                    )
                    print("[PythonBridge] Calling onSubtitle callback...")
                    self.onSubtitle?(entry)
                    print("[PythonBridge] onSubtitle callback done")
                }

            case "status":
                if let status = json["status"] as? String {
                    self.onStatusChange?(status)
                }

            case "error":
                if let message = json["message"] as? String {
                    self.onError?(message)
                }

            default:
                print("[PythonBridge] Unknown message type: \(type)")
            }
        }
    }

    // MARK: - venv Setup

    /// 設置 Python 虛擬環境
    private func setupVenv() async throws {
        // 確保父目錄存在
        let appSupportDir = venvPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: appSupportDir,
            withIntermediateDirectories: true
        )

        // 1. 建立 venv
        let pythonPath = try findSystemPython()
        print("[PythonBridge] Creating venv with: \(pythonPath.path)")

        try await runProcess(
            executable: pythonPath,
            arguments: ["-m", "venv", venvPath.path],
            errorType: { PythonBridgeError.venvSetupFailed($0) }
        )

        // 2. 安裝依賴
        let pipPath = venvPath.appendingPathComponent("bin/pip")
        let requirementsPath = backendPath.appendingPathComponent("requirements.txt")

        print("[PythonBridge] Installing dependencies...")

        try await runProcess(
            executable: pipPath,
            arguments: ["install", "-r", requirementsPath.path],
            errorType: { PythonBridgeError.dependencyInstallFailed($0) }
        )
    }

    /// 查找系統 Python 3.11+（優先使用 3.12，避免 3.14 相容性問題）
    private func findSystemPython() throws -> URL {
        // 優先使用穩定版本的 Python（3.12 > 3.13 > 通用 python3）
        let commonPaths = [
            "/opt/homebrew/bin/python3.12",  // Homebrew Python 3.12 (最穩定)
            "/opt/homebrew/bin/python3.13",  // Homebrew Python 3.13
            "/usr/local/bin/python3.12",     // Homebrew Intel 3.12
            "/usr/local/bin/python3.13",     // Homebrew Intel 3.13
            "/opt/homebrew/bin/python3",     // Homebrew Apple Silicon (可能是 3.14)
            "/usr/local/bin/python3",        // Homebrew Intel
            "/usr/bin/python3"               // macOS 預設 (通常版本較舊)
        ]

        for path in commonPaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        throw PythonBridgeError.pythonNotFound
    }

    /// 執行 Process 並等待完成（非阻塞）
    /// 使用 terminationHandler + withCheckedContinuation 避免阻塞主線程
    private func runProcess(
        executable: URL,
        arguments: [String],
        errorType: (String) -> PythonBridgeError
    ) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        // 捕獲 stderr 用於錯誤訊息
        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()

        // 使用 continuation 包裝同步等待（避免阻塞主線程）
        await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in
                continuation.resume()
            }
        }

        // 檢查執行結果
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(decoding: errorData, as: UTF8.self)
            throw errorType("exit code: \(process.terminationStatus)\n\(errorOutput)")
        }
    }
}
