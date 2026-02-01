//
//  ConfigurationService.swift
//  AutoSub
//
//  設定讀寫服務（含 Keychain）
//  Phase 4 實作
//

import Foundation
import Security

/// Keychain 錯誤
enum KeychainError: Error {
    case saveFailed
    case loadFailed
    case deleteFailed
}

/// 設定服務
class ConfigurationService {
    static let shared = ConfigurationService()

    private let configFileName = "config.json"

    /// 設定檔目錄
    private var configDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("AutoSub")
    }

    /// 設定檔路徑
    private var configPath: URL {
        configDirectory.appendingPathComponent(configFileName)
    }

    // MARK: - Keychain 操作

    /// 儲存 API Key 到 Keychain
    func saveToKeychain(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.autosub.app",
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]

        // 先刪除舊的
        SecItemDelete(query as CFDictionary)

        // 新增
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed
        }
    }

    /// 從 Keychain 讀取 API Key
    func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.autosub.app",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    // MARK: - 設定檔操作

    /// 儲存設定（不含 API Keys）
    func saveConfiguration(_ config: Configuration) throws {
        // 建立目錄
        try FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true
        )

        // 儲存設定（不含敏感資料）
        var safeConfig = config
        safeConfig.deepgramApiKey = ""
        safeConfig.geminiApiKey = ""

        let data = try JSONEncoder().encode(safeConfig)
        try data.write(to: configPath)

        // API Keys 存到 Keychain
        if !config.deepgramApiKey.isEmpty {
            try saveToKeychain(key: "deepgramApiKey", value: config.deepgramApiKey)
        }
        if !config.geminiApiKey.isEmpty {
            try saveToKeychain(key: "geminiApiKey", value: config.geminiApiKey)
        }
    }

    /// 讀取設定
    func loadConfiguration() -> Configuration {
        var config: Configuration

        // 讀取設定檔
        if let data = try? Data(contentsOf: configPath),
           let loaded = try? JSONDecoder().decode(Configuration.self, from: data) {
            config = loaded
        } else {
            config = Configuration()
        }

        // 從 Keychain 讀取 API Keys
        if let deepgramKey = loadFromKeychain(key: "deepgramApiKey") {
            config.deepgramApiKey = deepgramKey
        }
        if let geminiKey = loadFromKeychain(key: "geminiApiKey") {
            config.geminiApiKey = geminiKey
        }

        return config
    }
}
