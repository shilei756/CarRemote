import Foundation

/// 神兽主题授权（网页版 /myth/check：白名单内的用户才能看到入口）
public enum MythService {

    public struct Access: Sendable {
        public let allowed: Bool
        public let isOwner: Bool
    }

    /// 当前手机号是否有神兽主题权限（网页版 mythAllowed / /myth/check）
    public static func check(phone: String) async -> Access {
        guard let url = URL(string: APIConfig.siteBaseURL + "/myth/check") else {
            return Access(allowed: false, isOwner: false)
        }
        guard let object = try? await APIClient.postJSON(url, json: ["phone": phone]),
              let dict = object as? [String: Any] else {
            // 网络异常时保守放行站主（本地快速预判，与网页版 MYTH_WHITELIST 思路一致）
            return Access(allowed: phone == APIConfig.ownerPhone, isOwner: phone == APIConfig.ownerPhone)
        }
        let allowed = dict.bool("allowed") ?? false
        let isOwner = dict.bool("is_owner") ?? false
        return Access(allowed: allowed || isOwner, isOwner: isOwner)
    }
}
