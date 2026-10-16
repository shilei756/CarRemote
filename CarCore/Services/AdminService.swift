import Foundation

/// 使用者记录（/admin/usage 返回的 items 元素）
public struct AdminUsageItem: Sendable, Equatable, Identifiable {
    public var id: String { phone }
    public let phone: String
    public let first: String
    public let last: String
    public let count: Int
    public let owner: Bool
    public let admin: Bool
    public let wl: Bool
    /// "ok" 体验中 / "unauth" 未授权 / "expired" 已过期
    public let card: String

    public init(phone: String, first: String, last: String, count: Int,
                owner: Bool, admin: Bool, wl: Bool, card: String) {
        self.phone = phone
        self.first = first
        self.last = last
        self.count = count
        self.owner = owner
        self.admin = admin
        self.wl = wl
        self.card = card
    }

    public var badgeText: String {
        if owner { return "站主" }
        if admin { return "管理员" }
        if wl { return "白名单" }
        if card == "ok" { return "体验" }
        return "未授权"
    }
}

/// 体验卡密
public struct AdminCard: Sendable, Equatable, Identifiable {
    public var id: String { code }
    public let code: String
    public let note: String
    public let expireDate: String
    public let usedBy: String
    public let remainMin: Int
    public let voided: Bool
    public let available: Bool

    public init(code: String, note: String, expireDate: String, usedBy: String,
                remainMin: Int, voided: Bool, available: Bool) {
        self.code = code
        self.note = note
        self.expireDate = expireDate
        self.usedBy = usedBy
        self.remainMin = remainMin
        self.voided = voided
        self.available = available
    }

    public var stateText: String {
        if voided { return "已作废" }
        if !usedBy.isEmpty && remainMin <= 0 { return "已到期" }
        if !usedBy.isEmpty { return "使用中" }
        if available { return "可用" }
        return "已过期"
    }
}

/// 管理面板数据（/admin/usage）
public struct AdminUsageData: Sendable {
    public let items: [AdminUsageItem]
    public let people: Int
    public let total: Int
    public let blocked: [String]
    public let isOwner: Bool
    public let admins: [String]
    public let wlEnabled: Bool
    public let whitelist: [String]

    public init(items: [AdminUsageItem], people: Int, total: Int, blocked: [String],
                isOwner: Bool, admins: [String], wlEnabled: Bool, whitelist: [String]) {
        self.items = items
        self.people = people
        self.total = total
        self.blocked = blocked
        self.isOwner = isOwner
        self.admins = admins
        self.wlEnabled = wlEnabled
        self.whitelist = whitelist
    }
}

/// 授权管理（白名单）面板服务，与网页版 /admin/* 接口完全一致。
/// 所有请求都带管理密码（password）与操作者手机号（caller）。
public enum AdminService {

    // MARK: - 登录态错误（对应网页版 /admin/usage 的响应分支）

    public enum AuthError: LocalizedError, Equatable {
        /// 密码体系未初始化：ownerInit=true 表示需要站主设全局密码（/admin/whitelist/init）
        case needInit(ownerInit: Bool)
        /// 非管理员
        case notAdmin
        /// 密码错误
        case wrongPassword
        /// 其他服务端错误
        case server(String)

        public var errorDescription: String? {
            switch self {
            case .needInit(let ownerInit):
                return ownerInit ? "尚未初始化管理密码" : "请先设置你的管理密码"
            case .notAdmin: return "仅管理员可查看"
            case .wrongPassword: return "管理密码错误"
            case .server(let message): return message
            }
        }
    }

    // MARK: - 登录 / 刷新

    /// 管理面板登录（也是刷新）：密码正确返回统计数据
    public static func login(password: String, caller: String) async throws -> AdminUsageData {
        let object = try await postAdminRaw(path: "/admin/usage", password: password, caller: caller, extra: [:])
        guard let dict = object as? [String: Any] else { throw APIError.decode("响应解析失败") }
        // 与网页版一致的分支判定：need_init > not_admin > wrong_pass > success
        if dict.bool("need_init") == true {
            throw AuthError.needInit(ownerInit: dict.bool("owner_init") ?? false)
        }
        if dict.bool("not_admin") == true {
            throw AuthError.notAdmin
        }
        if dict.bool("wrong_pass") == true {
            throw AuthError.wrongPassword
        }
        guard dict.bool("success") == true else {
            throw AuthError.server(dict.string("message") ?? "登录失败")
        }
        return usageData(from: dict)
    }

    /// 当前手机号是否有管理入口（网页版 /admin/is_admin）
    public static func isAdmin(phone: String) async -> Bool {
        guard let url = URL(string: APIConfig.siteBaseURL + "/admin/is_admin") else { return false }
        guard let object = try? await APIClient.postJSON(url, json: ["phone": phone]),
              let dict = object as? [String: Any] else { return false }
        return dict.bool("is_admin") ?? false
    }

    /// 站主初始化全局管理密码（首次使用，网页版 /admin/whitelist/init）
    public static func initWhitelist(password: String, caller: String) async throws {
        let object = try await postAdminRaw(path: "/admin/whitelist/init", password: password, caller: caller, extra: [:])
        guard (object as? [String: Any])?.bool("success") == true else {
            throw APIError.server((object as? [String: Any])?.string("message") ?? "设置失败")
        }
    }

    /// 管理员首次进入：设置自己的管理密码（网页版 /admin/pass/init）
    public static func initPassword(_ password: String, caller: String) async throws {
        let object = try await postAdminRaw(path: "/admin/pass/init", password: password, caller: caller, extra: [:])
        guard (object as? [String: Any])?.bool("success") == true else {
            throw APIError.server((object as? [String: Any])?.string("message") ?? "设置失败")
        }
    }

    // MARK: - 使用者操作

    /// 解除限制
    public static func unblock(password: String, phone: String, caller: String) async throws {
        try await postAdmin(path: "/admin/usage/unblock", password: password, caller: caller, extra: ["phone": phone])
    }

    /// 删除使用记录
    public static func deleteRecord(password: String, phone: String, caller: String) async throws {
        try await postAdmin(path: "/admin/usage/delete", password: password, caller: caller, extra: ["phone": phone])
    }

    /// 强制下线（清除对方登录凭证）
    public static func forceLogout(caller: String, target: String) async throws {
        guard let url = URL(string: APIConfig.siteBaseURL + "/api/auth/revoke") else {
            throw APIError.invalidURL
        }
        let object = try await APIClient.postJSON(url, json: ["caller": caller, "target": target])
        guard (object as? [String: Any])?.bool("success") == true else {
            throw APIError.server((object as? [String: Any])?.string("message") ?? "操作失败")
        }
    }

    // MARK: - 站主操作

    public static func toggleWhitelist(password: String, caller: String, enable: Bool) async throws {
        try await postAdmin(path: "/admin/wl/toggle", password: password, caller: caller, extra: ["enable": enable])
    }

    public static func addWhitelistPhone(password: String, phone: String, caller: String) async throws {
        try await postAdmin(path: "/admin/wl/add", password: password, caller: caller, extra: ["phone": phone])
    }

    public static func removeWhitelistPhone(password: String, phone: String, caller: String) async throws {
        try await postAdmin(path: "/admin/wl/remove", password: password, caller: caller, extra: ["phone": phone])
    }

    public static func addAdmin(password: String, phone: String, caller: String) async throws {
        try await postAdmin(path: "/admin/admins/add", password: password, caller: caller, extra: ["phone": phone])
    }

    public static func removeAdmin(password: String, phone: String, caller: String) async throws {
        try await postAdmin(path: "/admin/admins/remove", password: password, caller: caller, extra: ["phone": phone])
    }

    // MARK: - 卡密

    /// 生成卡密，返回新卡密列表
    public static func generateCards(password: String, caller: String, count: Int, note: String, expireDate: String) async throws -> [String] {
        let object = try await postAdmin(path: "/admin/card/generate", password: password, caller: caller, extra: [
            "count": count,
            "note": note,
            "expire_date": expireDate
        ])
        guard let dict = object as? [String: Any], dict.bool("success") == true else {
            throw APIError.server((object as? [String: Any])?.string("message") ?? "生成失败")
        }
        return (dict["codes"] as? [String]) ?? []
    }

    public static func listCards(password: String, caller: String) async throws -> [AdminCard] {
        let object = try await postAdmin(path: "/admin/card/list", password: password, caller: caller, extra: [:])
        guard let dict = object as? [String: Any], dict.bool("success") == true else {
            throw APIError.server((object as? [String: Any])?.string("message") ?? "加载失败")
        }
        let array = dict["cards"] as? [[String: Any]] ?? []
        return array.map { c in
            AdminCard(
                code: c.string("code") ?? "",
                note: c.string("note") ?? "",
                expireDate: c.string("expire_date") ?? "",
                usedBy: c.string("used_by") ?? "",
                remainMin: c.int("remain_min") ?? 0,
                voided: c.bool("void") ?? false,
                available: c.bool("available") ?? false
            )
        }
    }

    public static func voidCard(password: String, code: String, void: Bool, caller: String) async throws {
        try await postAdmin(path: "/admin/card/void", password: password, caller: caller, extra: ["code": code, "void": void])
    }

    public static func deleteCard(password: String, code: String, caller: String) async throws {
        try await postAdmin(path: "/admin/card/delete", password: password, caller: caller, extra: ["code": code])
    }

    // MARK: - 私有

    /// 原始请求：不做 success 判定，返回完整响应（登录态分支判定用）
    private static func postAdminRaw(path: String, password: String, caller: String, extra: [String: Any]) async throws -> Any {
        guard let url = URL(string: APIConfig.siteBaseURL + path) else {
            throw APIError.invalidURL
        }
        var json: [String: Any] = ["password": password, "caller": caller]
        extra.forEach { json[$0.key] = $0.value }
        return try await APIClient.postJSON(url, json: json)
    }

    /// 操作请求：success=false 时抛出服务端消息
    private static func postAdmin(path: String, password: String, caller: String, extra: [String: Any]) async throws -> Any {
        let object = try await postAdminRaw(path: path, password: password, caller: caller, extra: extra)
        guard let dict = object as? [String: Any] else { throw APIError.decode("响应解析失败") }
        guard dict.bool("success") == true else {
            throw APIError.server(dict.string("message") ?? "操作失败")
        }
        return object
    }

    private static func usageData(from dict: [String: Any]) -> AdminUsageData {
        let items = (dict["items"] as? [[String: Any]] ?? []).map { u in
            AdminUsageItem(
                phone: u.string("phone") ?? "",
                first: u.string("first") ?? "",
                last: u.string("last") ?? "",
                count: u.int("count") ?? 0,
                owner: u.bool("owner") ?? false,
                admin: u.bool("admin") ?? false,
                wl: u.bool("wl") ?? false,
                card: u.string("card") ?? ""
            )
        }
        return AdminUsageData(
            items: items,
            people: dict.int("people") ?? 0,
            total: dict.int("total") ?? 0,
            blocked: (dict["blocked"] as? [String]) ?? [],
            isOwner: dict.bool("is_owner") ?? false,
            admins: (dict["admins"] as? [String]) ?? [],
            wlEnabled: dict.bool("wl_enabled") ?? false,
            whitelist: (dict["whitelist"] as? [String]) ?? []
        )
    }
}
