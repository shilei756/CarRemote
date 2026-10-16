import Foundation

/// 卡密体验系统（站主后台生成 CH-XXXX-XXXX 卡密，兑换当天体验权限）。
/// 正式用户（站主/管理员/白名单）不会进入体验网关。
public enum CardService {

    public struct CardStatus: Sendable {
        /// 是否有权限进入（正式用户或今日已兑换）
        public let authorized: Bool
        public let isRegular: Bool
        public let todayOK: Bool
        public let expiryText: String?
        public let message: String?

        public init(authorized: Bool, isRegular: Bool, todayOK: Bool, expiryText: String?, message: String?) {
            self.authorized = authorized
            self.isRegular = isRegular
            self.todayOK = todayOK
            self.expiryText = expiryText
            self.message = message
        }
    }

    /// 查询手机号的授权状态
    public static func status(phone: String) async throws -> CardStatus {
        guard let url = URL(string: APIConfig.siteBaseURL + "/api/card/status") else {
            throw APIError.invalidURL
        }
        let object = try await APIClient.postJSON(url, json: ["phone": phone])
        guard let dict = object as? [String: Any] else {
            // 接口异常时不阻塞登录（服务端仍会二次校验）
            return CardStatus(authorized: true, isRegular: true, todayOK: true, expiryText: nil, message: nil)
        }
        let isRegular = dict.bool("regular") ?? false
        let todayOK = dict.bool("today_ok") ?? false
        let authorized = isRegular || todayOK
        var expiry: String?
        if let date = dict.string("card_exp_date"), !date.isEmpty {
            expiry = date
        } else if let mode = dict.string("card_exp_mode"), !mode.isEmpty {
            expiry = mode
        }
        return CardStatus(
            authorized: authorized,
            isRegular: isRegular,
            todayOK: todayOK,
            expiryText: expiry,
            message: dict.string("message")
        )
    }

    /// 验证卡密，成功返回 true
    public static func verify(phone: String, code: String) async throws -> Bool {
        guard let url = URL(string: APIConfig.siteBaseURL + "/api/card/verify") else {
            throw APIError.invalidURL
        }
        let object = try await APIClient.postJSON(url, json: ["phone": phone, "code": code])
        guard let dict = object as? [String: Any] else {
            throw APIError.server("验证失败，请稍后重试")
        }
        if dict.bool("success") == true { return true }
        throw APIError.server(dict.string("message") ?? "卡密无效或已使用")
    }
}
