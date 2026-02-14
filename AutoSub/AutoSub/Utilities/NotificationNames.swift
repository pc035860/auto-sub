//
//  NotificationNames.swift
//  AutoSub
//
//  統一定義所有應用程式通知名稱
//

import Foundation

// MARK: - Notification Names

extension Notification.Name {
    // MARK: 快捷鍵相關

    /// 切換擷取狀態（⌘ + Shift + S）
    static let toggleCapture = Notification.Name("AutoSub.toggleCapture")

    /// 切換字幕顯示（⌘ + Shift + H）
    static let toggleSubtitle = Notification.Name("AutoSub.toggleSubtitle")

    // MARK: 字幕視窗相關

    /// 字幕鎖定狀態變更
    static let subtitleLockStateChanged = Notification.Name("AutoSub.subtitleLockStateChanged")

    /// 字幕視窗大小調整開始
    static let subtitleResizeStarted = Notification.Name("AutoSub.subtitleResizeStarted")

    /// 字幕視窗大小調整結束
    static let subtitleResizeEnded = Notification.Name("AutoSub.subtitleResizeEnded")

    /// 字幕視窗大小調整中（userInfo 包含 width 和 height）
    static let subtitleResizing = Notification.Name("AutoSub.subtitleResizing")
}
