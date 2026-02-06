import Security
import Foundation
import os

enum KeychainManager {
    private static let logger = Logger(subsystem: "com.quickai", category: "Keychain")
    private static var service: String {
        if let override = ProcessInfo.processInfo.environment["QUICK_AI_KEYCHAIN_SERVICE"],
           !override.isEmpty {
            return override
        }
        return "dev.camin.Quick-AI"
    }

    @discardableResult
    static func save(key: String, value: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return true
        }

        guard addStatus == errSecDuplicateItem else {
            logger.error("Keychain save failed for '\(key, privacy: .public)' with status: \(addStatus)")
            return false
        }

        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, attributes as CFDictionary)
        guard updateStatus == errSecSuccess else {
            logger.error("Keychain update failed for '\(key, privacy: .public)' with status: \(updateStatus)")
            return false
        }

        return true
    }

    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                logger.error("Keychain read failed for '\(key, privacy: .public)' with status: \(status)")
            }
            return nil
        }

        guard let data = result as? Data else {
            logger.error("Keychain read returned invalid payload for '\(key, privacy: .public)'")
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed for '\(key, privacy: .public)' with status: \(status)")
            return false
        }
        return true
    }
}
