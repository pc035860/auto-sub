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
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private var windowDelegate: SubtitleWindowDelegate?
    private weak var appState: AppState?

    /// 淡出任務
    private var fadeOutTask: Task<Void, Never>?
    /// 是否正在淡出中
    private(set) var isFadingOut: Bool = false

    /// 初始化
    init() {}

    /// 設定 AppState 參考
    func configure(appState: AppState) {
        self.appState = appState
        setupResizeObservers()
    }

    private func setupResizeObservers() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResizeStarted),
            name: .subtitleResizeStarted,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResizeEnded),
            name: .subtitleResizeEnded,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleResizing(_:)),
            name: .subtitleResizing,
            object: nil
        )
    }

    @objc private func handleResizeStarted() {
        appState?.isResizingSubtitle = true
        window?.isMovableByWindowBackground = false
    }

    @objc private func handleResizeEnded() {
        appState?.isResizingSubtitle = false
        if let appState = appState {
            window?.isMovableByWindowBackground = !appState.isSubtitleLocked
            appState.saveConfiguration()
        } else {
            window?.isMovableByWindowBackground = true
        }
    }

    @objc private func handleResizing(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let width = userInfo["width"] as? CGFloat,
              let height = userInfo["height"] as? CGFloat else { return }
        Task { @MainActor [weak self] in
            self?.resizeWindowDirectly(width: width, height: height)
        }
    }

    /// 直接調整視窗大小（不透過 Combine observer，避免抖動）
    private func resizeWindowDirectly(width: CGFloat, height: CGFloat) {
        guard let window = window else { return }

        let currentFrame = window.frame
        // 從右下角調整：保持左上角位置不變
        let newFrame = NSRect(
            x: currentFrame.origin.x,
            y: currentFrame.origin.y - (height - currentFrame.height),
            width: width,
            height: height
        )

        window.setFrame(newFrame, display: true)
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
        window?.isMovableByWindowBackground = appState.isResizingSubtitle ? false : !appState.isSubtitleLocked
        print("[SubtitleWindow] Mouse events ignored: \(appState.isSubtitleLocked)")
    }

    /// 套用字幕渲染設定（寬度、尺寸）
    func applyRenderSettings() {
        guard let window = window else { return }
        let screen = window.screen ?? NSScreen.main
        guard let screenFrame = screen?.visibleFrame else { return }

        let newSize = resolvedWindowSize(for: screenFrame)
        let currentFrame = window.frame

        var newFrame: NSRect
        // 如果正在拖拉調整大小，保持位置不變
        if appState?.isResizingSubtitle == true {
            // 保持位置，只調整大小（從右下角調整）
            newFrame = NSRect(
                x: currentFrame.origin.x,
                y: currentFrame.origin.y - (newSize.height - currentFrame.height),
                width: newSize.width,
                height: newSize.height
            )
        } else {
            // 重新計算位置（居中）
            var newX = currentFrame.midX - newSize.width / 2
            var newY = currentFrame.origin.y

            // 確保視窗在螢幕範圍內
            newX = max(screenFrame.minX, min(newX, screenFrame.maxX - newSize.width))
            newY = max(screenFrame.minY, min(newY, screenFrame.maxY - newSize.height))

            newFrame = NSRect(x: newX, y: newY, width: newSize.width, height: newSize.height)
        }

        window.setFrame(newFrame, display: true)
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

        // 建立視窗
        window = SubtitleWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = false
        window?.level = NSWindow.Level(rawValue: 1000)  // 高於 screenSaver，確保覆蓋全螢幕 app
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]  // 移除 .stationary 以允許拖動
        window?.ignoresMouseEvents = true  // 預設鎖定
        window?.isMovableByWindowBackground = true  // 允許拖動

        // 設定視窗委派（偵測拖動結束）
        windowDelegate = SubtitleWindowDelegate()
        windowDelegate?.onDragEnd = { [weak self] in
            self?.saveCurrentPosition()
        }
        window?.delegate = windowDelegate

        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        window?.contentView = hostingView
    }

    private func resolvedWindowSize(for screenFrame: NSRect) -> CGSize {
        let minWidth: CGFloat = 400
        let maxWidth = screenFrame.width * 0.95
        let defaultWidth = screenFrame.width * 0.8
        let configuredWidth = appState?.subtitleWindowWidth ?? 0
        let rawWidth = configuredWidth > 0 ? configuredWidth : defaultWidth
        let width = max(minWidth, min(rawWidth, maxWidth))
        let minHeight: CGFloat = 120
        let maxHeight = screenFrame.height * 0.6
        let defaultHeight = screenFrame.height * 0.2
        let configuredHeight = appState?.subtitleWindowHeight ?? 0
        let rawHeight = configuredHeight > 0 ? configuredHeight : defaultHeight
        let height = max(minHeight, min(rawHeight, maxHeight))
        return CGSize(width: width, height: height)
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
class SubtitleWindow: NSWindow {
    // 使用 NSWindowDelegate 偵測拖動結束（見 SubtitleWindowDelegate）
}

/// 視窗委派，處理拖動結束事件
class SubtitleWindowDelegate: NSObject, NSWindowDelegate {
    var onDragEnd: (() -> Void)?

    func windowDidMove(_ notification: Notification) {
        // 視窗移動結束時觸發
        onDragEnd?()
    }
}
