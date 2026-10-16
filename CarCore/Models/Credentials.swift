import Foundation

/// 登录凭据：手机号 + 控车码 + 官网刷新令牌 + 车联网访问令牌缓存。
public struct Credentials: Codable, Equatable, Sendable {
    public var phone: String
    public var pin: String
    public var refToken: String
    public var accessToken: String?
    public var accessTokenExpiry: Date?

    public init(phone: String, pin: String, refToken: String,
                accessToken: String? = nil, accessTokenExpiry: Date? = nil) {
        self.phone = phone
        self.pin = pin
        self.refToken = refToken
        self.accessToken = accessToken
        self.accessTokenExpiry = accessTokenExpiry
    }

    /// access_token 是否仍在有效期内（预留 60 秒安全余量）
    public var hasValidAccessToken: Bool {
        guard let token = accessToken, !token.isEmpty,
              let expiry = accessTokenExpiry else { return false }
        return Date().addingTimeInterval(60) < expiry
    }

    /// 脱敏手机号，如 185****4954
    public var maskedPhone: String {
        guard phone.count == 11 else { return phone }
        return phone.prefix(3) + "****" + phone.suffix(4)
    }
}
