//
//  SubtitleOverlay.swift
//  AutoSub
//
//  字幕覆蓋層視圖
//  支援歷史字幕顯示（3 筆）、透明度遞減、翻譯中狀態
//

import AppKit
import SwiftUI

// MARK: - 多語言字體支援

extension Font {
    /// 建立支援多語言（中、英、日）的字體（粗體）
    /// macOS 系統會自動根據文字內容選擇合適的字體：
    /// - 中文：PingFang SC/TC 或 Hiragino Sans
    /// - 日文：Hiragino Sans 或 Yu Gothic
    /// - 英文：SF Pro（系統預設）
    static func multilingualSystem(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        // 使用 .system() 搭配明確的 size 和 weight
        // macOS 會自動處理多語言字體 fallback
        return .system(size: size, weight: weight, design: .default)
    }
}

struct SubtitleOverlay: View {
    @EnvironmentObject var appState: AppState
    @State private var isPinnedToBottom: Bool = true
    @State private var didInitialScroll: Bool = false
    // 每筆字幕列高度只增不減，避免翻譯中/完成時高度塌縮造成跳動
    @State private var rowMinHeightById: [UUID: CGFloat] = [:]
    @State private var previousHistoryIds: [UUID] = []
    @State private var lastInterimHeight: CGFloat = 0
    @State private var lastKnownContentWidth: CGFloat = 0

    /// 歷史字幕的透明度（最舊 → 最新）
    private let opacityLevels: [Double] = [0.3, 0.6, 1.0]
    private let minOpacity: Double = 0.3

    var body: some View {
        VStack(spacing: 0) {
            if !appState.isSubtitleLocked {
                HStack(spacing: 4) {
                    Spacer()
                    OpacityQuickMenu(appState: appState)
                }
                .padding(.trailing, 8)
                .padding(.top, 8)
            }

            // 字幕內容（帶捲軸）
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: !appState.isSubtitleLocked) {
                    VStack(spacing: 8) {
                        ForEach(Array(appState.subtitleHistory.enumerated()), id: \.element.id) { index, entry in
                            SubtitleRow(
                                entry: entry,
                                showOriginal: appState.showOriginalText,
                                minReservedHeight: rowMinHeightById[entry.id]
                            ) { measuredHeight in
                                updateRowMinHeight(for: entry.id, measuredHeight: measuredHeight)
                            }
                                .opacity(opacityForIndex(index))
                                .id(entry.id)
                        }

                        // Interim（正在說的話）
                        if let interim = appState.currentInterim, !interim.isEmpty {
                            InterimRow(text: interim) { measuredHeight in
                                updateInterimHeight(measuredHeight)
                            }
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
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: SubtitleContentWidthPreferenceKey.self,
                                value: max(0, geometry.size.width - 40)
                            )
                        }
                    )
                    .onPreferenceChange(SubtitleContentWidthPreferenceKey.self) { width in
                        guard width > 0 else { return }
                        lastKnownContentWidth = width
                    }
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
                .onChangeCompat(of: appState.subtitleHistory.map(\.id)) {
                    syncRowHeightCacheAndSeed(for: appState.subtitleHistory)
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
                .onAppear {
                    syncRowHeightCacheAndSeed(for: appState.subtitleHistory)
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

    private func syncRowHeightCacheAndSeed(for history: [SubtitleEntry]) {
        let historyIds = history.map(\.id)
        let historyIdSet = Set(historyIds)
        rowMinHeightById = rowMinHeightById.filter { historyIdSet.contains($0.key) }

        let previousIdSet = Set(previousHistoryIds)
        let newEntries = history.filter { !previousIdSet.contains($0.id) }

        var consumedInterimSeed = false
        for entry in newEntries {
            let usedInterim = seedReservedHeightIfNeeded(for: entry, allowInterimSeed: !consumedInterimSeed)
            if usedInterim {
                consumedInterimSeed = true
            }
        }

        if consumedInterimSeed {
            lastInterimHeight = 0
        }
        previousHistoryIds = historyIds
    }

    @discardableResult
    private func seedReservedHeightIfNeeded(for entry: SubtitleEntry, allowInterimSeed: Bool) -> Bool {
        guard !appState.showOriginalText, entry.isTranslating else { return false }

        let width = resolvedContentWidth()
        let originalHeight = estimateTextHeight(
            entry.originalText,
            fontSize: appState.subtitleFontSize * 0.85,
            width: width
        )
        let placeholderHeight = estimateTextHeight(
            "翻譯中...",
            fontSize: appState.subtitleFontSize,
            width: width,
            isItalic: true
        )
        let interimSeed = allowInterimSeed ? lastInterimHeight : 0
        let seed = max(interimSeed, originalHeight, placeholderHeight)

        guard seed > 0 else { return false }
        updateRowMinHeight(for: entry.id, measuredHeight: seed)
        return interimSeed > 0.5
    }

    private func updateRowMinHeight(for id: UUID, measuredHeight: CGFloat) {
        let normalizedHeight = ceil(max(0, measuredHeight))
        guard normalizedHeight > 0 else { return }

        let current = rowMinHeightById[id] ?? 0
        guard normalizedHeight > current + 0.5 else { return }
        rowMinHeightById[id] = normalizedHeight
    }

    private func updateInterimHeight(_ measuredHeight: CGFloat) {
        let normalizedHeight = ceil(max(0, measuredHeight))
        guard normalizedHeight > 0 else { return }
        lastInterimHeight = max(lastInterimHeight, normalizedHeight)
    }

    private func resolvedContentWidth() -> CGFloat {
        if lastKnownContentWidth > 0 {
            return max(80, lastKnownContentWidth)
        }
        if appState.subtitleWindowWidth > 0 {
            return max(80, appState.subtitleWindowWidth - 40)
        }
        if let screenWidth = NSScreen.main?.visibleFrame.width {
            return max(80, (screenWidth * 0.8) - 40)
        }
        return 600
    }

    private func estimateTextHeight(
        _ text: String,
        fontSize: CGFloat,
        width: CGFloat,
        isItalic: Bool = false
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }

        let baseFont = NSFont.systemFont(ofSize: max(1, fontSize), weight: .bold)
        let font = isItalic
            ? NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
            : baseFont
        let bounds = (text as NSString).boundingRect(
            with: NSSize(width: max(1, width), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font]
        )
        return ceil(bounds.height)
    }
}

// MARK: - SubtitleRow

/// 單筆字幕列
struct SubtitleRow: View {
    let entry: SubtitleEntry
    let showOriginal: Bool
    let minReservedHeight: CGFloat?
    let onMeasuredHeight: (CGFloat) -> Void

    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // 原文
            if showOriginal {
                SubtitleText(
                    text: entry.originalText,
                    font: .multilingualSystem(size: appState.subtitleFontSize * 0.85),
                    textColor: .orange.opacity(0.8),
                    isItalic: false,
                    outlineEnabled: appState.subtitleTextOutlineEnabled
                )
            }

            // 翻譯（或翻譯中提示）
            if let translation = entry.translatedText {
                SubtitleText(
                    text: translation,
                    font: .multilingualSystem(size: appState.subtitleFontSize),
                    textColor: entry.wasRevised ? .mint : .white,
                    isItalic: false,
                    outlineEnabled: appState.subtitleTextOutlineEnabled
                )
            } else {
                SubtitleText(
                    text: "翻譯中...",
                    font: .multilingualSystem(size: appState.subtitleFontSize),
                    textColor: .gray,
                    isItalic: true,
                    outlineEnabled: appState.subtitleTextOutlineEnabled
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: minReservedHeight, alignment: .leading)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: SubtitleRowHeightPreferenceKey.self, value: geometry.size.height)
            }
        )
        .onPreferenceChange(SubtitleRowHeightPreferenceKey.self, perform: onMeasuredHeight)
    }
}

// MARK: - InterimRow

/// Interim 文字列（正在說的話）
struct InterimRow: View {
    let text: String
    let onMeasuredHeight: (CGFloat) -> Void

    @EnvironmentObject var appState: AppState

    var body: some View {
        SubtitleText(
            text: text,
            font: .multilingualSystem(size: appState.subtitleFontSize * 0.85),
            textColor: .cyan.opacity(0.8),
            isItalic: true,
            outlineEnabled: appState.subtitleTextOutlineEnabled
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: SubtitleRowHeightPreferenceKey.self, value: geometry.size.height)
            }
        )
        .onPreferenceChange(SubtitleRowHeightPreferenceKey.self, perform: onMeasuredHeight)
    }
}

private struct SubtitleRowHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct SubtitleContentWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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

/// 透明度快速切換選單（解鎖時顯示）
struct OpacityQuickMenu: View {
    @ObservedObject var appState: AppState

    /// 暫存自訂透明度值，切換到預設後仍可切回
    @State private var cachedCustomValue: Double?

    private static let presets: [(label: String, value: Double)] = [
        ("全透明", 0.00),
        ("透明", 0.40),
        ("淡", 0.60),
        ("中", 0.80),
        ("深", 0.95),
    ]

    /// 目前值是否匹配任何預設檔位（±0.02 容差）
    private var isCustom: Bool {
        !Self.presets.contains { abs(appState.subtitleWindowOpacity - $0.value) < 0.02 }
    }

    /// 用來顯示的自訂值：優先顯示目前值（如果是自訂），否則顯示暫存值
    private var displayCustomValue: Double? {
        if isCustom { return appState.subtitleWindowOpacity }
        return cachedCustomValue
    }

    var body: some View {
        Menu {
            ForEach(Self.presets, id: \.value) { preset in
                Button {
                    // 切換到預設前，如果目前是自訂值就暫存
                    if isCustom {
                        cachedCustomValue = appState.subtitleWindowOpacity
                    }
                    appState.subtitleWindowOpacity = preset.value
                    appState.saveConfiguration()
                } label: {
                    HStack {
                        Text("\(preset.label) \(percentText(preset.value))")
                        if isSelected(preset.value) {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            // 自訂選項：目前是自訂值，或有暫存的自訂值時顯示
            if let customValue = displayCustomValue {
                Divider()
                Button {
                    appState.subtitleWindowOpacity = customValue
                    appState.saveConfiguration()
                } label: {
                    HStack {
                        Text("自訂 \(percentText(customValue))")
                        if isSelected(customValue) {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .onAppear {
            // 初始化時若為自訂值，暫存起來
            if isCustom {
                cachedCustomValue = appState.subtitleWindowOpacity
            }
        }
    }

    private func isSelected(_ value: Double) -> Bool {
        abs(appState.subtitleWindowOpacity - value) < 0.02
    }

    private func percentText(_ value: Double) -> String {
        "\(Int(round(value * 100)))%"
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
