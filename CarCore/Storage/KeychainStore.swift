import Foundation
import Security

/// 共享 Keychain 存储（App 与小组件通过 keychain-access-groups 共享）。
/// 模拟器不支持 Access Group，自动降级为普通 Keychain。
public enum KeychainStore {

    private static let service = "app.copper1249.chipmunk6639.keychain"

    private static func query(forKey key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = APIConfig.keychainAccessGroup
        #endif
        return query
    }

    public static func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        // 先删后写，避免 SecItemUpdate 的复杂性
        _ = SecItemDelete(query(forKey: key) as CFDictionary)
        var item = query(forKey: key)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        _ = SecItemAdd(item as CFDictionary, nil)
    }

    public static func get(_ key: String) -> String? {
        var item = query(forKey: key)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func remove(_ key: String) {
        _ = SecItemDelete(query(forKey: key) as CFDictionary)
    }
}
