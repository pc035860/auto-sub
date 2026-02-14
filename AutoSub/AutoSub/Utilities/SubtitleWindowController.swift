//
//  SubtitleWindowController.swift
//  AutoSub
//
//  字幕視窗管理
//  支援拖動、鎖定、位置保存
//

import AppKit
import SwiftUI

/// 字幕視窗控制器
@MainActor
final class SubtitleWindowController {
    private let minimumWindowSize = NSSize(width: 100, height: 100)

    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var windowDelegate: SubtitleWindowDelegate?
    private weak var appState: AppState?
    private var isApplyingRenderSettings = false
    private var isUserLiveResizing = false

    /// 淡出任務
    private var fadeOutTask: Task<Void, Never>?
    /// 是否正在淡出中
    private(set) var isFadingOut: Bool = false

    /// 初始化
    init() {}

    /// 設定 AppState 參考
    func configure(appState: AppState) {
        self.appState = appState
    }

    /// 顯示字幕視窗
    func show<Content: View>(content: Content) {
        print("[SubtitleWindow] show() called")
        if window == nil {
            print("[SubtitleWindow] Creating window...")
            createWindow()
        }

        hostingView?.rootView = AnyView(content)

        // 恢復儲存的位置
        restorePosition()

        // 更新滑鼠事件處理
        updateMouseEventHandling()

        // 更新視窗大小
        applyRenderSettings()

        window?.orderFront(nil)
        print("[SubtitleWindow] Window shown, frame: \(window?.frame ?? .zero)")
    }

    /// 隱藏字幕視窗
    func hide() {
        window?.orderOut(nil)
    }

    /// 延遲後淡出隱藏字幕視窗
    /// - Parameters:
    ///   - delay: 延遲秒數（預設 3 秒）
    ///   - duration: 淡出動畫秒數（預設 2 秒）
    func hideWithFadeOut(delay: TimeInterval = 3.0, duration: TimeInterval = 2.0) {
        // 取消之前的淡出任務
        fadeOutTask?.cancel()
        fadeOutTask = Task { [weak self] in
            guard let self, let window = self.window else { return }

            // 延遲
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            // 檢查是否被取消
            guard !Task.isCancelled else { return }

            // 執行淡出動畫
            await MainActor.run {
                self.isFadingOut = true
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = duration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().alphaValue = 0
                } completionHandler: { [weak self] in
                    // 動畫完成後隱藏視窗
                    window.orderOut(nil)
                    window.alphaValue = 1.0
                    Task { @MainActor [weak self] in
                        self?.isFadingOut = false
                    }
                }
            }
        }
    }

    /// 取消淡出並恢復視窗透明度
    func cancelFadeOutIfNeeded() {
        fadeOutTask?.cancel()
        fadeOutTask = nil
        isFadingOut = false
        window?.alphaValue = 1.0
    }

    /// 更新滑鼠事件處理（鎖定狀態變更時呼叫）
    func updateMouseEventHandling() {
        guard let appState = appState else { return }
        window?.ignoresMouseEvents = appState.isSubtitleLocked
        window?.isMovableByWindowBackground = !appState.isSubtitleLocked
        print("[SubtitleWindow] Mouse events ignored: \(appState.isSubtitleLocked)")
    }

    /// 套用字幕渲染設定（寬度、尺寸）
    func applyRenderSettings() {
        guard let window = window else { return }
        guard !isUserLiveResizing else { return }
        let screen = window.screen ?? NSScreen.main
        guard let screenFrame = screen?.visibleFrame else { return }
        updateWindowResizeLimits(for: screenFrame)

        let newSize = resolvedWindowSize(for: screenFrame)
        let currentFrame = window.frame

        var newFrame = currentFrame
        newFrame.size = newSize
        newFrame.origin.x = max(screenFrame.minX, min(newFrame.origin.x, screenFrame.maxX - newSize.width))
        newFrame.origin.y = max(screenFrame.minY, min(newFrame.origin.y, screenFrame.maxY - newSize.height))

        guard !framesAreAlmostEqual(newFrame, currentFrame) else { return }
        isApplyingRenderSettings = true
        window.setFrame(newFrame, display: true)
        isApplyingRenderSettings = false
    }

    /// 重設位置到預設
    func resetPosition() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        let width = min(screenFrame.width * 0.8, window?.frame.width ?? 600)
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + 50

        window?.setFrameOrigin(NSPoint(x: x, y: y))

        appState?.subtitlePositionX = x
        appState?.subtitlePositionY = y
        appState?.saveSubtitlePosition()
        print("[SubtitleWindow] Position reset to default: (\(x), \(y))")
    }

    // MARK: - Private

    private func createWindow() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // 計算初始位置和尺寸
        let size = resolvedWindowSize(for: screenFrame)
        let x = screenFrame.origin.x + (screenFrame.width - size.width) / 2
        let y = screenFrame.origin.y + 50

        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)

        // 建立原生可縮放視窗（保留 overlay 外觀）
        window = SubtitleWindow(
            contentRect: frame,
            styleMask: [.titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window?.titleVisibility = .hidden
        window?.titlebarAppearsTransparent = true
        window?.standardWindowButton(.closeButton)?.isHidden = true
        window?.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window?.standardWindowButton(.zoomButton)?.isHidden = true
        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = false
        window?.level = NSWindow.Level(rawValue: 1000)  // 高於 screenSaver，確保覆蓋全螢幕 app
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window?.ignoresMouseEvents = true  // 預設鎖定
        window?.isMovableByWindowBackground = false
        updateWindowResizeLimits(for: screenFrame)

        // 設定視窗委派（拖動、縮放同步）
        windowDelegate = SubtitleWindowDelegate()
        windowDelegate?.onMove = { [weak self] in
            self?.saveCurrentPosition()
        }
        windowDelegate?.onWillResize = { [weak self] sender, frameSize in
            guard let self else { return frameSize }
            let screenFrame = (sender.screen ?? NSScreen.main)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
            return self.clampedWindowSize(for: frameSize, screenFrame: screenFrame)
        }
        windowDelegate?.onResize = { [weak self] resizedWindow in
            self?.syncResizedWindowSize(resizedWindow)
        }
        windowDelegate?.onResizeEnded = { [weak self] in
            self?.isUserLiveResizing = false
            self?.appState?.saveConfiguration()
        }
        windowDelegate?.onResizeStarted = { [weak self] in
            self?.isUserLiveResizing = true
        }
        window?.delegate = windowDelegate

        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        window?.contentView = hostingView
    }

    private func resolvedWindowSize(for screenFrame: NSRect) -> CGSize {
        let defaultWidth = screenFrame.width * 0.8
        let defaultHeight = screenFrame.height * 0.2
        let configuredWidth = appState?.subtitleWindowWidth ?? 0
        let configuredHeight = appState?.subtitleWindowHeight ?? 0
        let rawSize = NSSize(
            width: configuredWidth > 0 ? configuredWidth : defaultWidth,
            height: configuredHeight > 0 ? configuredHeight : defaultHeight
        )
        return clampedWindowSize(for: rawSize, screenFrame: screenFrame)
    }

    private func clampedWindowSize(for size: NSSize, screenFrame: NSRect) -> NSSize {
        let minWidth = minimumWindowSize.width
        let minHeight = minimumWindowSize.height
        let maxWidth = screenFrame.width * 0.95
        let maxHeight = screenFrame.height * 0.6

        let clampedWidth = max(minWidth, min(size.width, maxWidth))
        let clampedHeight = max(minHeight, min(size.height, maxHeight))
        return NSSize(width: clampedWidth, height: clampedHeight)
    }

    private func updateWindowResizeLimits(for screenFrame: NSRect) {
        let maxSize = clampedWindowSize(
            for: NSSize(width: screenFrame.width, height: screenFrame.height),
            screenFrame: screenFrame
        )
        window?.contentMinSize = minimumWindowSize
        window?.contentMaxSize = maxSize
    }

    private func syncResizedWindowSize(_ resizedWindow: NSWindow) {
        guard !isApplyingRenderSettings else { return }
        guard let appState = appState else { return }

        let screenFrame = (resizedWindow.screen ?? NSScreen.main)?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let clampedSize = clampedWindowSize(for: resizedWindow.frame.size, screenFrame: screenFrame)

        if abs(clampedSize.width - resizedWindow.frame.width) > 0.5 ||
            abs(clampedSize.height - resizedWindow.frame.height) > 0.5 {
            isApplyingRenderSettings = true
            var frame = resizedWindow.frame
            frame.size = clampedSize
            resizedWindow.setFrame(frame, display: true)
            isApplyingRenderSettings = false
        }

        if abs(appState.subtitleWindowWidth - clampedSize.width) > 0.5 {
            appState.subtitleWindowWidth = clampedSize.width
        }
        if abs(appState.subtitleWindowHeight - clampedSize.height) > 0.5 {
            appState.subtitleWindowHeight = clampedSize.height
        }
    }

    private func framesAreAlmostEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5 &&
            abs(lhs.origin.y - rhs.origin.y) < 0.5 &&
            abs(lhs.size.width - rhs.size.width) < 0.5 &&
            abs(lhs.size.height - rhs.size.height) < 0.5
    }

    private func restorePosition() {
        guard let window = window,
              let appState = appState else { return }

        appState.loadSubtitlePosition()

        if let x = appState.subtitlePositionX,
           let y = appState.subtitlePositionY {
            window.setFrameOrigin(NSPoint(x: x, y: y))
            print("[SubtitleWindow] Position restored: (\(x), \(y))")
        }
    }

    private func saveCurrentPosition() {
        guard let window = window,
              let appState = appState else { return }

        appState.subtitlePositionX = window.frame.origin.x
        appState.subtitlePositionY = window.frame.origin.y
        appState.saveSubtitlePosition()
        print("[SubtitleWindow] Position saved: (\(window.frame.origin.x), \(window.frame.origin.y))")
    }
}

/// 自訂視窗類別
class SubtitleWindow: NSWindow {}

/// 視窗委派，處理拖動與縮放事件
class SubtitleWindowDelegate: NSObject, NSWindowDelegate {
    var onMove: (() -> Void)?
    var onResize: ((NSWindow) -> Void)?
    var onResizeEnded: (() -> Void)?
    var onResizeStarted: (() -> Void)?
    var onWillResize: ((NSWindow, NSSize) -> NSSize)?

    func windowDidMove(_ notification: Notification) {
        onMove?()
    }

    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        onWillResize?(sender, frameSize) ?? frameSize
    }

    func windowDidResize(_ notification: Notification) {
        guard let resizedWindow = notification.object as? NSWindow else { return }
        onResize?(resizedWindow)
    }

    func windowWillStartLiveResize(_ notification: Notification) {
        onResizeStarted?()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        onResizeEnded?()
    }
}
