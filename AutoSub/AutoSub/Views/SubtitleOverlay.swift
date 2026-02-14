//
//  SubtitleOverlay.swift
//  AutoSub
//
//  字幕覆蓋層視圖
//  支援歷史字幕顯示（3 筆）、透明度遞減、翻譯中狀態
//

import SwiftUI
import AppKit

struct SubtitleOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var isPinnedToBottom: Bool = true
    @State private var didInitialScroll: Bool = false
    @State private var resizeStartSize: CGSize = .zero
    @State private var resizeStartMouseLocation: NSPoint = .zero
    @State private var isDraggingResize: Bool = false

    /// 歷史字幕的透明度（最舊 → 最新）
    private let opacityLevels: [Double] = [0.3, 0.6, 1.0]
    private let minOpacity: Double = 0.3

    /// 最小視窗尺寸
    private let minWindowSize = CGSize(width: 400, height: 120)

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
                .onChangeCompat(of: appState.currentInterim) {
                    // interim 更新時捲到底部（不帶動畫，避免高頻更新造成抖動）
                    if appState.currentInterim != nil, isPinnedToBottom {
                        proxy.scrollTo("scrollBottom", anchor: .bottom)
                    }
                }
            }

            // 解鎖時顯示拖拉角標
            if !appState.isSubtitleLocked {
                HStack {
                    Spacer()
                    ResizeHandle(
                        onDragChanged: { dragValue in
                            handleResize(dragValue: dragValue)
                        },
                        onDragEnded: {
                            saveResizeResult()
                        }
                    )
                }
                .padding(.trailing, 4)
                .padding(.bottom, 4)
            }
        }
        .frame(maxWidth: maxWidth, maxHeight: maxHeight)
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
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                        )
                }
            }
        )
    }

    // MARK: - Resize Handling

    private func handleResize(dragValue _: DragGesture.Value) {
        // 記錄起始尺寸（首次拖拉時）
        if !isDraggingResize {
            isDraggingResize = true
            NotificationCenter.default.post(name: .subtitleResizeStarted, object: nil)
            resizeStartMouseLocation = NSEvent.mouseLocation
            let currentWidth = appState.subtitleWindowWidth > 0
                ? appState.subtitleWindowWidth
                : (NSScreen.main?.visibleFrame.width ?? 1200) * 0.8
            let currentHeight = appState.subtitleWindowHeight > 0
                ? appState.subtitleWindowHeight
                : (NSScreen.main?.visibleFrame.height ?? 800) * 0.2
            resizeStartSize = CGSize(width: currentWidth, height: currentHeight)
        }

        // 使用螢幕座標避免 SwiftUI 在 macOS 的手勢座標方向差異
        let currentMouseLocation = NSEvent.mouseLocation
        let deltaX = currentMouseLocation.x - resizeStartMouseLocation.x
        let deltaY = currentMouseLocation.y - resizeStartMouseLocation.y
        let newWidth = max(minWindowSize.width, resizeStartSize.width + deltaX)
        let newHeight = max(minWindowSize.height, resizeStartSize.height - deltaY)

        // 同時更新 appState（為了下次拖拉的起始值）和通知視窗控制器
        appState.subtitleWindowWidth = newWidth
        appState.subtitleWindowHeight = newHeight

        NotificationCenter.default.post(
            name: .subtitleResizing,
            object: nil,
            userInfo: ["width": newWidth, "height": newHeight]
        )
    }

    private func saveResizeResult() {
        isDraggingResize = false
        NotificationCenter.default.post(name: .subtitleResizeEnded, object: nil)
    }

    /// 最大寬度（螢幕 80%，但絕對不超過 1200px）
    private var maxWidth: CGFloat {
        let screenWidth = NSScreen.main?.visibleFrame.width ?? 1920
        let configuredWidth = appState.subtitleWindowWidth > 0 ? appState.subtitleWindowWidth : screenWidth * 0.8
        return min(min(configuredWidth, screenWidth * 0.95), 1200)
    }

    /// 最大高度（螢幕 20%）
    private var maxHeight: CGFloat {
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 1080
        let configuredHeight = appState.subtitleWindowHeight > 0 ? appState.subtitleWindowHeight : screenHeight * 0.2
        return min(configuredHeight, screenHeight * 0.6)
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

// MARK: - DragHandle

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

/// 拖拉角標（右下角調整大小）
struct ResizeHandle: View {
    var onDragChanged: (DragGesture.Value) -> Void
    var onDragEnded: () -> Void

    var body: some View {
        Image(systemName: "arrow.down.left.and.arrow.up.right")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.white.opacity(0.7))
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.15))
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        onDragChanged(value)
                    }
                    .onEnded { _ in
                        onDragEnded()
                    }
            )
            .help("拖曳調整視窗大小")
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
