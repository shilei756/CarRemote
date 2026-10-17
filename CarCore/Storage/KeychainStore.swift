import Foundation
import Security

/// 共享 Keychain 存储（App 与小组件通过 keychain-access-groups 共享）。
///
/// 全能签/重签兼容（关键）：
/// 访问组必须是「当前签名证书的团队前缀 + .carremote」。硬编码原始团队
/// （7NSH43RT4Z）在换证书重签后会因前缀不匹配导致钥匙串读写全部静默失败
/// ——主 App 有兜底看不出异常，小组件却读不到任何数据。
/// 因此这里在运行时从代码签名信息里提取真实 team id 动态拼组名，
/// 主 App 与小组件（同一张证书重签）算出的组名必然一致。
/// 模拟器不支持 Access Group，自动降级为普通 Keychain。
public enum KeychainStore {

    private static let service = "app.copper1249.chipmunk6639.keychain"

    /// 缓存当前签名证书的团队前缀（进程生命周期内不变）
    private static var cachedTeamID: String?

    /// 从代码签名信息提取 team id（iOS 常用做法；失败时回退原始团队）
    private static var teamID: String {
        if let cachedTeamID { return cachedTeamID }
        var team = "7NSH43RT4Z"
        var codeRef: SecCode?
        if SecCodeCopySelf([], &codeRef) == errSecSuccess, let codeRef {
            var staticRef: SecStaticCode?
            if SecCodeCopyStaticCode(codeRef, [], &staticRef) == errSecSuccess, let staticRef {
                var infoRef: CFDictionary?
                // kSecCSSigningInformation = 1 << 1
                if SecCodeCopySigningInformation(staticRef, SecCSFlags(rawValue: 2), &infoRef) == errSecSuccess,
                   let info = infoRef as? [String: Any],
                   let extracted = info["teamid"] as? String,
                   !extracted.isEmpty {
                    team = extracted
                }
            }
        }
        cachedTeamID = team
        return team
    }

    /// 当前应使用的钥匙串访问组候选（按顺序尝试）
    private static func accessGroups() -> [String] {
        #if targetEnvironment(simulator)
        return []
        #else
        return ["\(teamID).carremote", "7NSH43RT4Z.carremote"]
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
        var lastError: OSStatus = errSecSuccess
        for group in accessGroups() {
            var item = baseQuery(forKey: key)
            item[kSecAttrAccessGroup as String] = group
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let status = SecItemAdd(item as CFDictionary, nil)
            if status == errSecSuccess { return }
            lastError = status
        }
        // 所有候选组都失败（无 keychain 权限）：退回默认组（本进程可读，保主 App 正常）
        var item = baseQuery(forKey: key)
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        _ = SecItemAdd(item as CFDictionary, nil)
        _ = lastError
    }

    public static func get(_ key: String) -> String? {
        // 依次尝试各候选组 + 无组（默认组）
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
