//
//  SubtitleOverlay.swift
//  AutoSub
//
//  字幕覆蓋層視圖
//  支援歷史字幕顯示（3 筆）、透明度遞減、翻譯中狀態
//

import SwiftUI

struct SubtitleOverlay: View {
    @EnvironmentObject var appState: AppState

    /// 歷史字幕的透明度（最舊 → 最新）
    private let opacityLevels: [Double] = [0.3, 0.6, 1.0]

    var body: some View {
        VStack(spacing: 0) {
            // 解鎖時顯示拖曳把手
            if !appState.isSubtitleLocked {
                HStack {
                    Spacer()
                    DragHandle {
                        // 點擊把手鎖定字幕
                        appState.isSubtitleLocked = true
                        appState.saveSubtitlePosition()
                        // 通知視窗控制器更新滑鼠事件處理
                        NotificationCenter.default.post(name: .subtitleLockStateChanged, object: nil)
                    }
                }
                .padding(.trailing, 8)
                .padding(.top, 4)
            }

            // 字幕內容（帶捲軸）
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(Array(appState.subtitleHistory.enumerated()), id: \.element.id) { index, entry in
                            SubtitleRow(entry: entry, showOriginal: appState.showOriginalText)
                                .opacity(opacityForIndex(index))
                                .id(entry.id)
                        }

                        // Interim（正在說的話）
                        if let interim = appState.currentInterim, !interim.isEmpty {
                            InterimRow(text: interim)
                                .id("interim")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .onChangeCompat(of: appState.subtitleHistory.count) {
                    // 新字幕進來時自動捲到底部
                    if let lastId = appState.subtitleHistory.last?.id {
                        withAnimation {
                            proxy.scrollTo(lastId, anchor: .bottom)
                        }
                    }
                }
                .onChangeCompat(of: appState.currentInterim) {
                    // interim 更新時捲到底部（不帶動畫，避免高頻更新造成抖動）
                    if appState.currentInterim != nil {
                        proxy.scrollTo("interim", anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.7))
        )
    }

    /// 最大寬度（螢幕 80%）
    private var maxWidth: CGFloat {
        (NSScreen.main?.visibleFrame.width ?? 1920) * 0.8
    }

    /// 最大高度（螢幕 20%）
    private var maxHeight: CGFloat {
        (NSScreen.main?.visibleFrame.height ?? 1080) * 0.2
    }

    /// 根據索引計算透明度
    private func opacityForIndex(_ index: Int) -> Double {
        let count = appState.subtitleHistory.count
        let reversedIndex = count - 1 - index  // 0 = 最新, count-1 = 最舊

        if reversedIndex < opacityLevels.count {
            return opacityLevels[opacityLevels.count - 1 - reversedIndex]
        }
        return opacityLevels.first ?? 0.3
    }
}

// MARK: - SubtitleRow

/// 單筆字幕列
struct SubtitleRow: View {
    let entry: SubtitleEntry
    let showOriginal: Bool

    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 原文
            if showOriginal {
                Text(entry.originalText)
                    .font(.system(size: appState.subtitleFontSize * 0.85))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(nil)  // 不限制行數
                    .fixedSize(horizontal: false, vertical: true)  // 允許垂直擴展
            }

            // 翻譯（或翻譯中提示）
            if let translation = entry.translatedText {
                Text(translation)
                    .font(.system(size: appState.subtitleFontSize))
                    // Phase 2: 被修正過的翻譯用淺綠色顯示
                    .foregroundColor(entry.wasRevised ? .mint : .white)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("翻譯中...")
                    .font(.system(size: appState.subtitleFontSize))
                    .foregroundColor(.gray)
                    .italic()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - InterimRow

/// Interim 文字列（正在說的話）
struct InterimRow: View {
    let text: String

    @EnvironmentObject var appState: AppState

    var body: some View {
        Text(text)
            .font(.system(size: appState.subtitleFontSize * 0.85))
            .foregroundColor(.cyan.opacity(0.8))
            .italic()
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - DragHandle

/// 拖曳把手（點擊可切換鎖定狀態）
struct DragHandle: View {
    var onLockToggle: () -> Void

    var body: some View {
        Button(action: onLockToggle) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .help("點擊鎖定字幕位置")
    }
}

// MARK: - macOS 相容性擴展

extension View {
    /// macOS 13/14 相容的 onChange
    @ViewBuilder
    func onChangeCompat<V: Equatable>(of value: V, perform action: @escaping () -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, _ in action() }
        } else {
            self.onChange(of: value) { _ in action() }
        }
    }
}

// MARK: - Preview

#Preview {
    SubtitleOverlay()
        .environmentObject(AppState())
}
