import Foundation

/// 重签环境兼容层（全能签/爱思等工具重签后 entitlements 会变）。
///
/// 背景：CI 产出未签名 IPA，安装前由重签工具用自己的证书+描述文件签名。
/// 重签后：
/// - App Group 可能被改名为重签平台登记的组（或被剥离）；
/// - 钥匙串访问组的前缀会从原团队（7NSH43RT4Z.*）变成新团队；
/// 代码里写死组名会导致小组件与主 App 的三条共享通道全部失效
/// （表现为小组件「未登录」，诊断行 钥匙串✗ 共享存储✗ 容器文件✗）。
///
/// 解法：运行时解析本目标的 embedded.mobileprovision（重签工具一定会
/// 重新注入），从 Entitlements 里动态发现当前签名环境真正可用的
/// App Group 与钥匙串访问组，供 SharedStore / KeychainStore 遍历使用。
///
/// 提取原理：mobileprovision 是 CMS 签名容器，内嵌的 plist 是裸 XML，
/// 直接按 `<?xml` … `</plist>` 字节边界切出来反序列化即可（无需 OpenSSL）。
public enum ResignCompat {

    private static let lock = NSLock()
    private static var cache: ResignInfo?

    public struct ResignInfo {
        /// 描述文件 Entitlements 里声明的 App Group（可能为空）
        public let appGroups: [String]
        /// 描述文件 Entitlements 里声明的钥匙串访问组（可能为空）
        public let keychainGroups: [String]
        /// 是否成功读到描述文件（App Store 正式包没有此文件 → false）
        public let profileFound: Bool
    }

    /// 解析结果缓存（进程内只解析一次）
    public static func resignInfo() -> ResignInfo {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        let info = parse()
        cache = info
        return info
    }

    /// 候选 App Group：描述文件声明的组优先级低于工程默认组
    /// （默认组放前面：保证老用户已写入的数据优先命中）。
    public static func candidateAppGroups() -> [String] {
        var groups = [APIConfig.appGroupIdentifier]
        groups.append(contentsOf: resignInfo().appGroups)
        return groups.uniqued
    }

    /// 候选钥匙串访问组（不含默认组兜底，KeychainStore 会自动追加）
    public static func candidateKeychainGroups() -> [String] {
        var groups = [APIConfig.keychainAccessGroup]
        groups.append(contentsOf: resignInfo().keychainGroups)
        return groups.uniqued
    }

    // MARK: - 解析

    private static func parse() -> ResignInfo {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let raw = try? Data(contentsOf: url) else {
            return ResignInfo(appGroups: [], keychainGroups: [], profileFound: false)
        }
        guard let plist = embeddedPlist(in: raw),
              let entitlements = plist["Entitlements"] as? [String: Any] else {
            return ResignInfo(appGroups: [], keychainGroups: [], profileFound: true)
        }
        let appGroups = entitlements["com.apple.security.application-groups"] as? [String] ?? []
        let kcGroups = entitlements["keychain-access-groups"] as? [String] ?? []
        return ResignInfo(appGroups: appGroups, keychainGroups: kcGroups, profileFound: true)
    }

    /// 从 CMS 容器字节流中切出内嵌的 XML plist
    private static func embeddedPlist(in data: Data) -> [String: Any]? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let xml = data.subdata(in: start.lowerBound..<end.upperBound)
        return (try? PropertyListSerialization.propertyList(
            from: xml, options: [], format: nil)) as? [String: Any]
    }
}

private extension Array where Element: Equatable {
    /// 去重保序
    var uniqued: [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
