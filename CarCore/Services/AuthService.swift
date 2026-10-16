import Foundation

/// 手机号检查结果（白名单 / 封禁）
public struct PhoneCheck: Sendable {
    public let blocked: Bool
    public let unauthorized: Bool
    public let message: String?

    public init(blocked: Bool, unauthorized: Bool, message: String?) {
        self.blocked = blocked
        self.unauthorized = unauthorized
        self.message = message
    }
}

/// 登录 / 注册 / 令牌服务
public enum AuthService {

    /// 手机号 + 控车码登录（与网页版 /get_user_info 一致）
    public static func login(phone: String, pin: String) async throws -> Credentials {
        guard phone.count == 11, phone.hasPrefix("1") else {
            throw APIError.server("请输入正确的 11 位手机号")
        }
        guard !pin.isEmpty else {
            throw APIError.server("请输入控车码")
        }
        guard var components = URLComponents(string: APIConfig.siteBaseURL + "/get_user_info") else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "phone", value: phone),
            URLQueryItem(name: "pin", value: pin)
        ]
        let object = try await APIClient.getJSON(components.url!, headers: ["Content-Type": "application/json"])
        guard let dict = object as? [String: Any], dict.bool("success") == true else {
            let message = (object as? [String: Any])?.string("message") ?? "用户不存在或控车码错误"
            throw APIError.server(message)
        }
        let refToken = dict.string("ref_token") ?? ""
        guard !refToken.isEmpty else {
            throw APIError.server("登录凭证异常，请重新登录")
        }
        return Credentials(phone: phone, pin: dict.string("pin") ?? pin, refToken: refToken)
    }

    /// 检查手机号状态（被封禁 / 未授权）
    public static func checkPhone(_ phone: String) async throws -> PhoneCheck {
        guard let url = URL(string: APIConfig.siteBaseURL + "/check_phone_exists") else {
            throw APIError.invalidURL
        }
        let object = try await APIClient.postJSON(url, json: ["phone": phone])
        let dict = object as? [String: Any] ?? [:]
        return PhoneCheck(
            blocked: dict.bool("blocked") ?? false,
            unauthorized: dict.bool("unauthorized") ?? false,
            message: dict.string("message")
        )
    }

    /// 发送短信验证码（新用户注册）
    public static func sendSMSCode(_ phone: String) async throws {
        guard phone.count == 11, phone.hasPrefix("1") else {
            throw APIError.server("请输入正确的 11 位手机号")
        }
        guard let url = URL(string: APIConfig.siteBaseURL + "/get_code") else {
            throw APIError.invalidURL
        }
        let object = try await APIClient.postJSON(url, json: ["mobile": phone])
        let dict = object as? [String: Any] ?? [:]
        guard dict.bool("success") != false else {
            throw APIError.server(dict.string("message") ?? "验证码发送失败")
        }
    }

    /// 短信注册 / 登录（新用户设置控车码）
    public static func register(phone: String, code: String, pin: String) async throws -> Credentials {
        guard let url = URL(string: APIConfig.siteBaseURL + "/register_user") else {
            throw APIError.invalidURL
        }
        let object = try await APIClient.postJSON(url, json: [
            "phone": phone,
            "verifyCode": code,
            "pin": pin
        ])
        guard let dict = object as? [String: Any], dict.bool("success") == true else {
            let message = (object as? [String: Any])?.string("message") ?? "注册失败，请检查验证码"
            throw APIError.server(message)
        }
        let refToken = dict.string("ref_token") ?? ""
        guard !refToken.isEmpty else {
            throw APIError.server("注册成功但未返回凭证，请改用登录")
        }
        return Credentials(phone: phone, pin: pin, refToken: refToken)
    }

    /// 获取有效的车联网 access_token（带缓存，自动刷新）。
    /// 返回最新的凭据（调用方应保存，以便缓存新 token）。
    public static func validAccessToken(for credentials: Credentials) async throws -> (token: String, credentials: Credentials) {
        if credentials.hasValidAccessToken, let token = credentials.accessToken {
            return (token, credentials)
        }
        guard var components = URLComponents(string: APIConfig.inCallTokenURL) else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "client_id", value: APIConfig.changanOAuthClientID),
            URLQueryItem(name: "refresh_token", value: credentials.refToken)
        ]
        let object = try await APIClient.getJSON(components.url!, headers: APIClient.changanHeaders)
        guard let dict = object as? [String: Any],
              let token = dict.string("access_token"), !token.isEmpty else {
            let message = (object as? [String: Any])?.string("message")
                ?? (object as? [String: Any])?.string("error")
                ?? "官网凭证已失效，请退出后重新登录"
            throw APIError.server(message)
        }
        let expiresIn = dict.double("expires_in") ?? 3600
        var updated = credentials
        updated.accessToken = token
        updated.accessTokenExpiry = Date().addingTimeInterval(max(60, expiresIn - 60))
        return (token, updated)
    }
}
