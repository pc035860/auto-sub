//
//  KeyboardShortcuts.swift
//  AutoSub
//
//  全域快捷鍵處理
//  Phase 4 實作
//

import AppKit
import Carbon

/// 快捷鍵管理
@MainActor
final class KeyboardShortcuts {
    static let shared = KeyboardShortcuts()

    private var eventMonitor: Any?

    /// 註冊全域快捷鍵
    func register() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
    }

    /// 取消註冊
    func unregister() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ⌘ + Shift + S：開始/停止
        if flags == [.command, .shift] && event.keyCode == 1 {  // 's'
            NotificationCenter.default.post(name: .toggleCapture, object: nil)
        }

        // ⌘ + Shift + H：隱藏字幕
        if flags == [.command, .shift] && event.keyCode == 4 {  // 'h'
            NotificationCenter.default.post(name: .toggleSubtitle, object: nil)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let toggleCapture = Notification.Name("AutoSub.toggleCapture")
    static let toggleSubtitle = Notification.Name("AutoSub.toggleSubtitle")
}
