import Foundation
import Security

/// 共享 Keychain 存储（App 与小组件通过 keychain-access-groups 共享）。
///
/// 重签兼容策略：
/// - 写入：先尝试声明的访问组，失败（entitlements 被重签工具改写/剥离）时
///   退回默认组，保证主 App 自身永远可用；
/// - 读取：先试访问组、再试默认组，两边对称。
/// - 模拟器不支持 Access Group，自动降级。
public enum KeychainStore {

    private static let service = "app.copper1249.chipmunk6639.keychain"

    /// 访问组候选（iOS 真机；模拟器返回空走默认 keychain）
    private static func accessGroups() -> [String] {
        #if targetEnvironment(simulator)
        return []
        #else
        return [APIConfig.keychainAccessGroup]
        #endif
    }

    /// 不带 access group 的基础查询
    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    public static func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        remove(key)
        for group in accessGroups() {
            var item = baseQuery(forKey: key)
            item[kSecAttrAccessGroup as String] = group
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            if SecItemAdd(item as CFDictionary, nil) == errSecSuccess { return }
        }
        // 候选组全部失败（entitlements 不匹配）：退回默认组保主 App 可用
        var item = baseQuery(forKey: key)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        _ = SecItemAdd(item as CFDictionary, nil)
    }

    public static func get(_ key: String) -> String? {
        for group in accessGroups() {
            var item = baseQuery(forKey: key)
            item[kSecAttrAccessGroup as String] = group
            item[kSecReturnData as String] = true
            item[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: AnyObject?
            if SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
               let data = result as? Data,
               let str = String(data: data, encoding: .utf8) {
                return str
            }
        }
        // 默认组兜底
        var item = baseQuery(forKey: key)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        if SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }

    public static func remove(_ key: String) {
        for group in accessGroups() {
            var item = baseQuery(forKey: key)
            item[kSecAttrAccessGroup as String] = group
            _ = SecItemDelete(item as CFDictionary)
        }
        _ = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
    }
}
