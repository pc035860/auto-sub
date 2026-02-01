//
//  AudioTestView.swift
//  AutoSub
//
//  Phase 2 測試用 View
//  用於驗證 AudioCaptureService 是否正常運作
//

import SwiftUI

/// 音訊擷取測試 View（開發用）
struct AudioTestView: View {
    @StateObject private var audioService = AudioCaptureService()
    @State private var isCapturing = false
    @State private var totalBytesReceived: Int = 0
    @State private var lastChunkSize: Int = 0
    @State private var errorMessage: String?
    @State private var savedFilePath: String?

    // 用於驗證格式的音訊緩衝區
    @State private var audioBuffer = Data()
    private let maxBufferSize = 24000 * 2 * 2 * 5  // 5 秒的音訊資料

    var body: some View {
        VStack(spacing: 20) {
            // 標題
            Text("Audio Capture Test")
                .font(.title)
                .bold()

            // 狀態顯示
            GroupBox("Status") {
                VStack(alignment: .leading, spacing: 8) {
                    statusRow("Capturing", value: isCapturing ? "Yes" : "No")
                    statusRow("Total Received", value: formatBytes(totalBytesReceived))
                    statusRow("Last Chunk", value: formatBytes(lastChunkSize))
                    statusRow("Volume", value: String(format: "%.4f", audioService.currentVolume))
                    statusRow("Has Activity", value: audioService.hasAudioActivity ? "Yes" : "No")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 音量指示器
            GroupBox("Volume Level") {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))

                        Rectangle()
                            .fill(volumeColor)
                            .frame(width: geometry.size.width * CGFloat(min(audioService.currentVolume * 10, 1.0)))
                    }
                }
                .frame(height: 20)
                .cornerRadius(4)
            }

            // 錯誤訊息
            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            // 控制按鈕
            HStack(spacing: 16) {
                Button(isCapturing ? "Stop Capture" : "Start Capture") {
                    Task {
                        await toggleCapture()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(isCapturing ? .red : .green)

                Button("Save 5s Audio") {
                    saveAudioSample()
                }
                .disabled(audioBuffer.isEmpty)
            }

            // 儲存路徑
            if let path = savedFilePath {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Audio saved to:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(path)
                        .font(.caption)
                        .textSelection(.enabled)
                }
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }

            // 格式說明
            GroupBox("Expected Format") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sample Rate: 24,000 Hz")
                    Text("Channels: 2 (Stereo)")
                    Text("Bit Depth: 16-bit (Int16)")
                    Text("Byte Order: Little-endian")
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
    }

    // MARK: - Helper Views

    private func statusRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label + ":")
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }

    private var volumeColor: Color {
        let volume = audioService.currentVolume
        if volume < 0.01 {
            return .gray
        } else if volume < 0.1 {
            return .green
        } else if volume < 0.5 {
            return .yellow
        } else {
            return .red
        }
    }

    // MARK: - Actions

    private func toggleCapture() async {
        if isCapturing {
            await audioService.stopCapture()
            isCapturing = false
        } else {
            // 設定音訊資料回呼
            audioService.onAudioData = { data in
                Task { @MainActor in
                    totalBytesReceived += data.count
                    lastChunkSize = data.count

                    // 累積到緩衝區（最多保留 5 秒）
                    audioBuffer.append(data)
                    if audioBuffer.count > maxBufferSize {
                        audioBuffer = audioBuffer.suffix(maxBufferSize)
                    }
                }
            }

            // 設定錯誤回呼
            audioService.onError = { error in
                Task { @MainActor in
                    errorMessage = error.localizedDescription
                }
            }

            do {
                try await audioService.startCapture()
                isCapturing = true
                errorMessage = nil
                totalBytesReceived = 0
                audioBuffer = Data()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveAudioSample() {
        guard !audioBuffer.isEmpty else { return }

        let filename = "audio_test_\(Date().timeIntervalSince1970).pcm"
        audioService.saveAudioForVerification(audioBuffer, to: filename)

        // 取得儲存路徑
        if let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {
            savedFilePath = documentsPath.appendingPathComponent(filename).path
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

// MARK: - Preview

#Preview {
    AudioTestView()
}
