//
//  SubtitleWindowController.swift
//  AutoSub
//
//  字幕視窗管理
//  Phase 4 實作
//

import AppKit
import SwiftUI

/// 字幕視窗控制器
@MainActor
final class SubtitleWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    /// 顯示字幕視窗
    func show<Content: View>(content: Content) {
        print("[SubtitleWindow] show() called")
        if window == nil {
            print("[SubtitleWindow] Creating window...")
            createWindow()
        }

        hostingView?.rootView = AnyView(content)
        window?.orderFront(nil)
        print("[SubtitleWindow] Window shown, frame: \(window?.frame ?? .zero)")
    }

    /// 隱藏字幕視窗
    func hide() {
        window?.orderOut(nil)
    }

    private func createWindow() {
        // 取得螢幕尺寸
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame

        // 字幕位置：螢幕底部，寬度 80%
        let width = screenFrame.width * 0.8
        let height: CGFloat = 120
        let x = screenFrame.origin.x + (screenFrame.width - width) / 2
        let y = screenFrame.origin.y + 50  // 距離底部 50pt

        let frame = NSRect(x: x, y: y, width: width, height: height)

        // 建立透明無邊框視窗
        window = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window?.isOpaque = false
        window?.backgroundColor = .clear
        window?.hasShadow = false
        window?.level = .screenSaver  // 最高層級，確保置頂
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window?.ignoresMouseEvents = true  // 點擊穿透
        window?.isMovableByWindowBackground = false

        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        window?.contentView = hostingView
    }
}
