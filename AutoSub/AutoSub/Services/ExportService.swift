//
//  ExportService.swift
//  AutoSub
//
//  字幕匯出服務
//

import Foundation

/// 匯出模式
enum ExportMode: String, CaseIterable {
    case bilingual = "雙語（原文 + 翻譯）"
    case originalOnly = "僅原文"
    case translationOnly = "僅翻譯"
}

/// 字幕匯出服務
struct ExportService {
    /// 匯出 SRT 格式
    /// - Parameters:
    ///   - subtitles: 字幕陣列
    ///   - startTime: Session 開始時間
    ///   - mode: 匯出模式
    /// - Returns: SRT 格式字串
    static func exportToSRT(
        _ subtitles: [SubtitleEntry],
        startTime: Date,
        mode: ExportMode
    ) -> String {
        var result = ""

        for (index, entry) in subtitles.enumerated() {
            // 序號（從 1 開始）
            result += "\(index + 1)\n"

            // 計算相對時間（從 Session 開始算起）
            let offset = entry.timestamp.timeIntervalSince(startTime)
            let startTimeStr = formatSRTTime(offset)
            // 結束時間 = 開始時間 + 3 秒（預估持續時間）
            let endTimeStr = formatSRTTime(offset + 3.0)
            result += "\(startTimeStr) --> \(endTimeStr)\n"

            // 內容（根據模式）
            switch mode {
            case .bilingual:
                result += "\(entry.originalText)\n"
                if let translation = entry.translatedText, !translation.isEmpty {
                    result += "\(translation)\n"
                }
            case .originalOnly:
                result += "\(entry.originalText)\n"
            case .translationOnly:
                if let translation = entry.translatedText, !translation.isEmpty {
                    result += "\(translation)\n"
                } else {
                    result += "\n"  // 空行佔位
                }
            }

            result += "\n"  // 空行分隔
        }

        return result
    }

    /// 格式化時間為 SRT 格式 (HH:MM:SS,mmm)
    private static func formatSRTTime(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        let millis = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
}
