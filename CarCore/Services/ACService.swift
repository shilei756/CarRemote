import Foundation

/// 空调控制模式（与网页版 setAcMode 完全一致）
public enum ACMode: String, Codable, CaseIterable, Sendable {
    case new = "新版"        // 网页版默认：开放平台链路（newAC），需扫码开通
    case official = "官方版" // 网页版 performAction：直连长安链路
}

/// 空调开通二维码
public struct ACQRCode: Sendable {
    /// 二维码图片数据（PNG）
    public let imageData: Data?
    /// 二维码图片 URL（服务端返回 URL 时使用）
    public let imageURL: URL?
    /// 轮询用 ID
    public let id: String
    /// 有效期（秒）
    public let ttl: Int
    /// 账号是否已有凭证
    public let hasExisting: Bool

    public init(imageData: Data?, imageURL: URL?, id: String, ttl: Int, hasExisting: Bool) {
        self.imageData = imageData
        self.imageURL = imageURL
        self.id = id
        self.ttl = ttl
        self.hasExisting = hasExisting
    }
}

/// 扫码状态
public struct ACQRStatus: Sendable {
    public enum Result: String, Sendable {
        case unauthorized // 未扫码
        case scanned      // 已扫码待确认
        case authorized   // 已授权
    }

    public let result: Result
    public let refreshToken: String?

    public init(result: Result, refreshToken: String?) {
        self.result = result
        self.refreshToken = refreshToken
    }
}

/// 空调官方正版链路（与网页版 newAC 完全一致）：
/// 1. 站内 /api/open/token 换取开放平台 refresh_token（扫码开通后由站点保存）
/// 2. 开放平台 /oauth/token 刷新 access_token
/// 3. open.car-control/{cmd} 下发指令
public enum ACService {

    // MARK: - 扫码开通

    /// 申请开通二维码
    public static func requestQRCode(phone: String, force: Bool = false) async throws -> ACQRCode {
        guard let url = URL(string: APIConfig.siteBaseURL + "/api/ac/qrcode") else {
            throw APIError.invalidURL
        }
        let object = try await APIClient.postJSON(url, json: ["phone": phone, "force": force])
        guard let dict = object as? [String: Any], dict.bool("success") == true else {
            let message = (object as? [String: Any])?.string("message") ?? "二维码生成失败"
            throw APIError.server(message)
        }
        var imageData: Data?
        var imageURL: URL?
        if let qr = dict.string("qrcode"), !qr.isEmpty {
            if qr.hasPrefix("data:image") {
                // data:image/png;base64,xxxx
                let base64 = String(qr.drop(while: { $0 != "," }).dropFirst())
                imageData = Data(base64Encoded: base64)
            } else if let url = URL(string: qr), qr.hasPrefix("http") {
                imageURL = url
            } else if let data = Data(base64Encoded: qr) {
                imageData = data
            }
        }
        guard let id = dict.string("qrcode_id"), !id.isEmpty else {
            throw APIError.server("二维码数据异常")
        }
        return ACQRCode(
            imageData: imageData,
            imageURL: imageURL,
            id: id,
            ttl: dict.int("ttl") ?? 180,
            hasExisting: dict.bool("has_existing") ?? false
        )
    }

    /// 轮询扫码状态
    public static func pollStatus(qrcodeId: String) async throws -> ACQRStatus {
        guard var components = URLComponents(string: APIConfig.siteBaseURL + "/api/ac/status") else {
            throw APIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "qrcode_id", value: qrcodeId)]
        let object = try await APIClient.getJSON(components.url!)
        guard let dict = object as? [String: Any], dict.bool("success") == true else {
            let message = (object as? [String: Any])?.string("message") ?? "二维码已失效"
            throw APIError.server(message)
        }
        let result = ACQRStatus.Result(rawValue: dict.string("result") ?? "unauthorized") ?? .unauthorized
        return ACQRStatus(result: result, refreshToken: dict.string("refresh_token"))
    }

    // MARK: - 官方正版指令

    /// 空调开通剩余天数（网页版 open_refresh_expire：refresh_token_expire_in 换算）。
    /// 链路：授权码 → 站内 /api/open/token 换 refresh_token → 开放平台 oauth 拿剩余秒数。
    /// 未开通 / 网络异常返回 nil（界面隐藏剩余天数）。
    public static func activationRemainingDays(credentials: Credentials) async -> Int? {
        // 优先本地缓存的到期时间，避免每次打开都走完整链路
        if let cached = SharedStore.loadACActivationExpire(), cached > Date() {
            return max(0, Int(cached.timeIntervalSinceNow / 86400))
        }
        // 1. 授权码（inCall access_token）
        guard let (authorizeToken, updated) = try? await AuthService.validAccessToken(for: credentials) else {
            return nil
        }
        SharedStore.saveCredentials(updated)

        // 2. 站内换取开放平台 refresh_token（未开通时服务端返回失败）
        guard let tokenURL = URL(string: APIConfig.siteBaseURL + "/api/open/token") else { return nil }
        guard let tokenObject = try? await APIClient.postJSON(tokenURL, json: [
            "phone": credentials.phone,
            "authorize_token": authorizeToken
        ]), let tokenDict = tokenObject as? [String: Any],
            tokenDict.bool("success") == true,
            let refreshToken = tokenDict.string("refresh_token"), !refreshToken.isEmpty else { return nil }

        // 3. 开放平台刷新，取 refresh_token_expire_in（剩余秒数）
        guard var oauthComponents = URLComponents(string: "https://open.iov.changan.com.cn/oauth/token") else { return nil }
        oauthComponents.queryItems = []
        let formBody = APIClient.formData([
            ("redict_uri", ""),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
            ("client_secret", "YjIzNWFmZDMxMzAwNDc4NQ=="),
            ("client_id", "b235afd313004785bfde580c188c47bb")
        ])
        let bodyData = formBody.data(using: String.Encoding.utf8)
        guard let oauthObject = try? await APIClient.request(
            oauthComponents.url!,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded"],
            body: bodyData
        ), let oauthDict = oauthObject as? [String: Any],
            let expireIn = oauthDict.int("refresh_token_expire_in") else { return nil }

        let expireDate = Date().addingTimeInterval(TimeInterval(expireIn))
        SharedStore.saveACActivationExpire(expireDate)
        return max(0, expireIn / 86400)
    }

    /// 通过长安开放平台执行空调指令（网页版 newAC）
    public static func executeOfficial(command: CarCommand, credentials: Credentials) async throws -> CommandResult {
        // 1. 授权码（inCall access_token，与 AuthService.validAccessToken 同一接口）
        let (authorizeToken, updated) = try await AuthService.validAccessToken(for: credentials)
        SharedStore.saveCredentials(updated)

        // 2. 车辆 ID
        let cars = try await CarService.fetchCars(accessToken: authorizeToken)
        guard let car = cars.first else {
            throw APIError.server("未获取到车辆信息")
        }

        // 3. 站内登录：授权码换取开放平台凭证。
        //    关键：只有走「授权码登录」的 access_token 才带车控（car-control）权限；
        //    库存 refresh_token 直接刷新出的 token scope 只有 car_info/user，
        //    下发指令会被网关拒绝（code=40001 服务未注册）。
        //    /api/open/login 服务端会用授权码做完整登录并保存新凭证。
        var accessToken = ""
        var chain = ""
        var diag = ""   // 诊断：链路 + 各接口原始返回
        do {
            let loginObject = try await APIClient.postJSON(
                URL(string: APIConfig.siteBaseURL + "/api/open/login")!,
                json: ["phone": credentials.phone, "authorize_token": authorizeToken]
            )
            let loginRaw = (try? JSONSerialization.data(withJSONObject: loginObject)).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
            if let loginDict = loginObject as? [String: Any],
               loginDict.bool("success") == true,
               let token = loginDict.string("access_token"), !token.isEmpty {
                accessToken = token
                chain = "login"
            }
            diag += "login=\(String(loginRaw.prefix(160))); "
        } catch {
            diag += "login_err=\(error.localizedDescription); "
        }

        // 4. 登录链失败时退回库存 refresh_token 刷新（权限可能不足，但保底可查）
        if accessToken.isEmpty {
            chain = "refresh"
            let tokenObject = try await APIClient.postJSON(
                URL(string: APIConfig.siteBaseURL + "/api/open/token")!,
                json: ["phone": credentials.phone, "authorize_token": authorizeToken]
            )
            guard let tokenDict = tokenObject as? [String: Any],
                  tokenDict.bool("success") == true,
                  let refreshToken = tokenDict.string("refresh_token"), !refreshToken.isEmpty else {
                let message = (tokenObject as? [String: Any])?.string("message") ?? "空调尚未开通，请先扫码开通"
                throw APIError.server(message)
            }
            let oauthForm = APIClient.formData([
                ("redict_uri", ""),
                ("refresh_token", refreshToken),
                ("grant_type", "refresh_token"),
                ("client_secret", "YjIzNWFmZDMxMzAwNDc4NQ=="),
                ("client_id", "b235afd313004785bfde580c188c47bb")
            ])
            let oauthObject = try await APIClient.request(
                URL(string: "https://open.iov.changan.com.cn/oauth/token")!,
                method: "POST",
                headers: ["Content-Type": "application/x-www-form-urlencoded"],
                body: oauthForm.data(using: String.Encoding.utf8)
            )
            guard let oauthDict = oauthObject as? [String: Any],
                  let token = oauthDict.string("access_token"), !token.isEmpty else {
                let message = (oauthObject as? [String: Any])?.string("error") ?? "开放平台凭证刷新失败，请重新扫码开通"
                throw APIError.server("\(message) [\(diag)]")
            }
            accessToken = token
            diag += "scope=\(oauthDict.string("scope") ?? "?"); "
        }
        diag += "chain=\(chain); "

        // 5. 下发指令（逐项对齐网页版 _newACGo：只带这几个头，不带 X-Requested-With）
        guard let executeURL = URL(string: "https://open.iov.changan.com.cn/openc-apigw/vrtm-agent/api/v2/open/car-control/\(command.rawValue)") else {
            throw APIError.invalidURL
        }
        let body: [String: Any] = [
            "mapArgsJson": "{}",
            "senderType": "APP",
            "cmd": command.rawValue,
            "carId": car.carId
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let headers: [String: String] = [
            "x-vcs-nonce": "WYYL",
            "x-vcs-user-access-token": accessToken,
            "x-vcs-timestamp": String(Int(Date().timeIntervalSince1970 * 1000)),
            "Content-Type": "application/json; charset=utf-8",
            "User-Agent": "okhttp/3.10.0"
        ]
        let (status, data) = try await APIClient.requestRaw(executeURL, method: "POST", headers: headers, body: bodyData)
        let text = String(data: data, encoding: .utf8) ?? ""
        let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let ok = dict.bool("success") == true
        var message = dict.string("msg") ?? dict.string("message")
            ?? (ok ? "指令已发送" : "车辆未接受指令")
        if !ok {
            let code = dict["code"].map { "\($0)" } ?? "-"
            let snippet = String(text.prefix(120))
            message = "\(message) [code=\(code) http=\(status) \(diag)raw=\(snippet)]"
        }
        return CommandResult(ok: ok, message: message)
    }
}
