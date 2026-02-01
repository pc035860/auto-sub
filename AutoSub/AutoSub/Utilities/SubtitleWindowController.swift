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
class SubtitleWindowController {
    private var window: NSWindow?
    private var hostingView: NSHostingView<AnyView>?

    /// 顯示字幕視窗
    func show<Content: View>(content: Content) {
        if window == nil {
            createWindow()
        }

        hostingView?.rootView = AnyView(content)
        window?.orderFront(nil)
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
        window?.level = .statusBar + 1  // 置頂
        window?.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window?.ignoresMouseEvents = true  // 點擊穿透

        hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        window?.contentView = hostingView
    }
}
