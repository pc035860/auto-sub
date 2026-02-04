//
//  ShortcutManager.swift
//  AutoSub
//
//  使用 KeyboardShortcuts 套件處理全域快捷鍵
//

import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleCapture = Self("toggleCapture")
    static let toggleSubtitle = Self("toggleSubtitle")
}

/// 全域快捷鍵管理
@MainActor
final class ShortcutManager {
    static let shared = ShortcutManager()
    private var isRegistered = false

    /// 註冊快捷鍵事件
    func register() {
        guard !isRegistered else { return }
        isRegistered = true

        KeyboardShortcuts.onKeyDown(for: .toggleCapture) {
            NotificationCenter.default.post(name: .toggleCapture, object: nil)
        }

        KeyboardShortcuts.onKeyDown(for: .toggleSubtitle) {
            NotificationCenter.default.post(name: .toggleSubtitle, object: nil)
        }
    }
}
