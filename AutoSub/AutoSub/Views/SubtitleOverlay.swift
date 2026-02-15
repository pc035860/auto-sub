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
    @State private var isPinnedToBottom: Bool = true
    @State private var didInitialScroll: Bool = false

    /// 歷史字幕的透明度（最舊 → 最新）
    private let opacityLevels: [Double] = [0.3, 0.6, 1.0]
    private let minOpacity: Double = 0.3

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                LockStateIcon(isLocked: appState.isSubtitleLocked)
            }
            .padding(.trailing, 8)
            .padding(.top, 4)

            // 字幕內容（帶捲軸）
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: !appState.isSubtitleLocked) {
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

                        // 捲動錨點（確保捲到容器底部）
                        Color.clear
                            .frame(height: 1)
                            .id("scrollBottom")
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        ScrollViewScrollObserver { scrollView in
                            let atBottom = appState.isSubtitleLocked
                                ? true
                                : ScrollViewScrollObserver.isAtBottom(scrollView: scrollView)
                            if isPinnedToBottom != atBottom {
                                DispatchQueue.main.async {
                                    isPinnedToBottom = atBottom
                                }
                            }
                        }
                    )
                }
                .scrollDisabled(appState.isSubtitleLocked)
                .onChangeCompat(of: appState.isSubtitleLocked) {
                    if appState.isSubtitleLocked {
                        DispatchQueue.main.async {
                            isPinnedToBottom = true
                            proxy.scrollTo("scrollBottom", anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    guard !didInitialScroll else { return }
                    didInitialScroll = true
                    DispatchQueue.main.async {
                        isPinnedToBottom = true
                        proxy.scrollTo("scrollBottom", anchor: .bottom)
                    }
                }
                .onChangeCompat(of: appState.subtitleHistory.count) {
                    // 新字幕進來時自動捲到底部
                    guard isPinnedToBottom else { return }
                    withAnimation {
                        proxy.scrollTo("scrollBottom", anchor: .bottom)
                    }
                }
                .onChangeCompat(of: appState.subtitleHistory.last?.translatedText) {
                    // 翻譯更新（含翻譯完成）時也要維持貼底，避免無新 transcript 時停在中間
                    guard isPinnedToBottom else { return }
                    proxy.scrollTo("scrollBottom", anchor: .bottom)
                }
                .onChangeCompat(of: appState.currentInterim) {
                    // interim 更新時捲到底部（不帶動畫，避免高頻更新造成抖動）
                    if appState.currentInterim != nil, isPinnedToBottom {
                        proxy.scrollTo("scrollBottom", anchor: .bottom)
                    }
                }
            }

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                // 背景填充
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(appState.subtitleWindowOpacity))

                // 解鎖時顯示虛線邊框
                if !appState.isSubtitleLocked {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            Color.white.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1, dash: [6, 4])
                        )
                }
            }
        )
    }

    /// 根據索引計算透明度
    private func opacityForIndex(_ index: Int) -> Double {
        let count = appState.subtitleHistory.count
        let reversedIndex = count - 1 - index  // 0 = 最新, count-1 = 最舊

        if appState.subtitleAutoOpacityByCount {
            guard count > 1 else { return 1.0 }
            let step = (1.0 - minOpacity) / Double(max(1, count - 1))
            return max(minOpacity, 1.0 - (Double(reversedIndex) * step))
        }

        return 1.0
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
                SubtitleText(
                    text: entry.originalText,
                    font: .system(size: appState.subtitleFontSize * 0.85),
                    textColor: .orange.opacity(0.8),
                    isItalic: false,
                    outlineEnabled: appState.subtitleTextOutlineEnabled
                )
            }

            // 翻譯（或翻譯中提示）
            if let translation = entry.translatedText {
                SubtitleText(
                    text: translation,
                    font: .system(size: appState.subtitleFontSize),
                    textColor: entry.wasRevised ? .mint : .white,
                    isItalic: false,
                    outlineEnabled: appState.subtitleTextOutlineEnabled
                )
            } else {
                SubtitleText(
                    text: "翻譯中...",
                    font: .system(size: appState.subtitleFontSize),
                    textColor: .gray,
                    isItalic: true,
                    outlineEnabled: appState.subtitleTextOutlineEnabled
                )
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
        SubtitleText(
            text: text,
            font: .system(size: appState.subtitleFontSize * 0.85),
            textColor: .cyan.opacity(0.8),
            isItalic: true,
            outlineEnabled: appState.subtitleTextOutlineEnabled
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - OutlinedText

struct OutlinedText: View {
    let text: String
    let font: Font
    let textColor: Color
    let strokeColor: Color
    let strokeWidth: CGFloat
    var isItalic: Bool = false

    var body: some View {
        ZStack {
            strokeLayer(offsetX: -strokeWidth, offsetY: 0)
            strokeLayer(offsetX: strokeWidth, offsetY: 0)
            strokeLayer(offsetX: 0, offsetY: -strokeWidth)
            strokeLayer(offsetX: 0, offsetY: strokeWidth)
            strokeLayer(offsetX: -strokeWidth, offsetY: -strokeWidth)
            strokeLayer(offsetX: -strokeWidth, offsetY: strokeWidth)
            strokeLayer(offsetX: strokeWidth, offsetY: -strokeWidth)
            strokeLayer(offsetX: strokeWidth, offsetY: strokeWidth)
            styledText(color: textColor)
        }
    }

    @ViewBuilder
    private func styledText(color: Color) -> some View {
        if isItalic {
            Text(text)
                .font(font)
                .foregroundColor(color)
                .italic()
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(font)
                .foregroundColor(color)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func strokeLayer(offsetX: CGFloat, offsetY: CGFloat) -> some View {
        styledText(color: strokeColor)
            .offset(x: offsetX, y: offsetY)
    }
}

struct SubtitleText: View {
    let text: String
    let font: Font
    let textColor: Color
    let isItalic: Bool
    let outlineEnabled: Bool

    var body: some View {
        if outlineEnabled {
            OutlinedText(
                text: text,
                font: font,
                textColor: textColor,
                strokeColor: .black,
                strokeWidth: 1,
                isItalic: isItalic
            )
        } else {
            styledText(color: textColor)
        }
    }

    @ViewBuilder
    private func styledText(color: Color) -> some View {
        if isItalic {
            Text(text)
                .font(font)
                .foregroundColor(color)
                .italic()
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(font)
                .foregroundColor(color)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 鎖定狀態圖示（純顯示，不可點擊）
struct LockStateIcon: View {
    let isLocked: Bool

    var body: some View {
        Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.1))
            )
            .allowsHitTesting(false)
            .help(isLocked ? "字幕已鎖定（請從 Menu Bar 解鎖）" : "字幕已解鎖（請從 Menu Bar 鎖定）")
    }
}

// MARK: - Scroll Observer

struct ScrollViewScrollObserver: NSViewRepresentable {
    let onScroll: (NSScrollView) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        Task { @MainActor in
            attachIfPossible(view, context: context)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            attachIfPossible(nsView, context: context)
        }
    }

    @MainActor
    private func attachIfPossible(_ nsView: NSView, context: Context) {
        guard let scrollView = nsView.enclosingScrollView else { return }
        context.coordinator.attach(to: scrollView)
    }

    static func isAtBottom(scrollView: NSScrollView) -> Bool {
        guard let documentView = scrollView.documentView else { return true }
        let contentHeight = documentView.frame.height
        let visibleRect = scrollView.documentVisibleRect

        if contentHeight <= visibleRect.height {
            return true
        }

        let threshold: CGFloat = 12
        if documentView.isFlipped {
            return (contentHeight - visibleRect.maxY) <= threshold
        }
        return visibleRect.minY <= threshold
    }

    final class Coordinator: NSObject {
        private let onScroll: (NSScrollView) -> Void
        private weak var scrollView: NSScrollView?

        init(onScroll: @escaping (NSScrollView) -> Void) {
            self.onScroll = onScroll
        }

        @MainActor
        func attach(to scrollView: NSScrollView) {
            if self.scrollView === scrollView { return }
            NotificationCenter.default.removeObserver(self)
            self.scrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleBoundsChanged(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        @objc
        private func handleBoundsChanged(_ notification: Notification) {
            guard let scrollView = scrollView else { return }
            onScroll(scrollView)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
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
