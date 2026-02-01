//
//  SubtitleOverlay.swift
//  AutoSub
//
//  字幕覆蓋層視圖
//

import SwiftUI

struct SubtitleOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var isVisible: Bool = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 4) {
            if let subtitle = appState.currentSubtitle {
                // 原文（日文）
                if appState.showOriginalText {
                    Text(subtitle.originalText)
                        .font(.system(size: appState.subtitleFontSize * 0.85))
                        .foregroundColor(.white.opacity(0.8))
                }

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
        .onAppear {
            // 視窗出現時立即顯示字幕
            if appState.currentSubtitle != nil {
                showSubtitle()
            }
        }
        .onChangeCompat(of: appState.currentSubtitle) {
            if appState.currentSubtitle != nil {
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

        // 設定自動隱藏計時器
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

#Preview {
    SubtitleOverlay()
        .environmentObject(AppState())
}
