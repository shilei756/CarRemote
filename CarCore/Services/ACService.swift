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

        var diag = ""
        // 2. 车辆候选：客户端 /user/cars + 服务端 /api/siri/cars（站点凭证查的，
        //    与网页版一致）。「服务未注册」往往就是 carId 不对，全部进入候选。
        var cars = try await CarService.fetchCars(accessToken: authorizeToken)
        do {
            let siriObject = try await APIClient.postJSON(
                URL(string: APIConfig.siteBaseURL + "/api/siri/cars")!,
                json: ["phone": credentials.phone, "pin": credentials.pin]
            )
            if let dict = siriObject as? [String: Any], dict.bool("success") == true,
               let array = dict["cars"] as? [[String: Any]] {
                let serverCars: [CarInfo] = array.compactMap { item in
                    guard let id = item.string("carId"), !id.isEmpty else { return nil }
                    let name = item.string("name") ?? ""
                    return CarInfo(carId: id, displayName: name)
                }
                if !serverCars.isEmpty {
                    diag += "serverCars=\(serverCars.map { $0.carId }.joined(separator: ",")); "
                    // 服务端列表（网页版视角）放前面优先尝试，去重合并
                    let clientIds = Set(cars.map { $0.carId })
                    cars = serverCars + cars.filter { !clientIds.contains($0.carId) }
                }
            }
        } catch { diag += "siriCars.err=\(error.localizedDescription); " }
        guard !cars.isEmpty else {
            throw APIError.server("未获取到车辆信息")
        }

        // 3. 组装候选 token（按可能性排序，全部尝试）：
        //    A. 网页版同款：/api/open/token(authorize) 的 refresh_token → oauth 刷新
        //    B. /api/open/login 返回的 refresh_token → oauth 刷新
        //    C. inCall 授权码直接当车控 token
        func oauthRefresh(_ refreshToken: String) async throws -> (String, String?) {
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
                let message = (oauthObject as? [String: Any])?.string("error") ?? "刷新失败"
                throw APIError.server(message)
            }
            // 关键：oauth 刷新会轮换 refresh_token，旧的立即作废（再刷只会拿到
            // scope=car_info user 的降级 token）。必须把最新的存回本地。
            if let rotated = oauthDict.string("refresh_token"), !rotated.isEmpty {
                SharedStore.saveACOpenRefreshToken(rotated)
            }
            return (token, oauthDict.string("scope"))
        }

        var tokenCandidates: [(label: String, token: String)] = []

        // A0. 本地最新轮换 token（自己上次刷新存下的，最新鲜、优先）
        if let localRT = SharedStore.loadACOpenRefreshToken() {
            do {
                let (token, scope) = try await oauthRefresh(localRT)
                tokenCandidates.append(("localtoken", token))
                diag += "A0.scope=\(scope ?? "?"); "
            } catch {
                diag += "A0.err=\(error.localizedDescription); "
                SharedStore.saveACOpenRefreshToken(nil)  // 已失效，清掉
            }
        }

        // A. 网页版同款链路
        do {
            let tokenObject = try await APIClient.postJSON(
                URL(string: APIConfig.siteBaseURL + "/api/open/token")!,
                json: ["phone": credentials.phone, "authorize_token": authorizeToken]
            )
            let raw = (try? JSONSerialization.data(withJSONObject: tokenObject)).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
            if let dict = tokenObject as? [String: Any], dict.bool("success") == true,
               let rt = dict.string("refresh_token"), !rt.isEmpty {
                let (token, scope) = try await oauthRefresh(rt)
                tokenCandidates.append(("webtoken", token))
                diag += "A.scope=\(scope ?? "?"); "
            } else {
                diag += "A.fail=\(String(raw.prefix(80))); "
            }
        } catch { diag += "A.err=\(error.localizedDescription); " }

        // B. 登录链
        do {
            let loginObject = try await APIClient.postJSON(
                URL(string: APIConfig.siteBaseURL + "/api/open/login")!,
                json: ["phone": credentials.phone, "authorize_token": authorizeToken]
            )
            if let dict = loginObject as? [String: Any], dict.bool("success") == true,
               let rt = dict.string("refresh_token"), !rt.isEmpty {
                let (token, scope) = try await oauthRefresh(rt)
                tokenCandidates.append(("logintoken", token))
                diag += "B.scope=\(scope ?? "?"); "
            }
        } catch { diag += "B.err=\(error.localizedDescription); " }

        // C. inCall 授权码直用
        tokenCandidates.append(("authorizetoken", authorizeToken))

        // 4. 下发：每个 token × 每个 carId 依次尝试，40001（服务未注册）换下一个组合
        let openCmd = command.openPlatformCmd
        guard let executeURL = URL(string: "https://open.iov.changan.com.cn/openc-apigw/vrtm-agent/api/v2/open/car-control/\(openCmd)") else {
            throw APIError.invalidURL
        }
        var lastCode = ""
        var lastRaw = ""
        var lastMessage = "车辆未接受指令"
        var ok = false
        var attemptLog = ""
        outer: for candidate in tokenCandidates {
            for car in cars {
                let body: [String: Any] = [
                    "mapArgsJson": "{}",
                    "senderType": "APP",
                    "cmd": openCmd,
                    "carId": car.carId
                ]
                let bodyData = try JSONSerialization.data(withJSONObject: body)
                let headers: [String: String] = [
                    "x-vcs-nonce": "WYYL",
                    "x-vcs-user-access-token": candidate.token,
                    "x-vcs-timestamp": String(Int(Date().timeIntervalSince1970 * 1000)),
                    "Content-Type": "application/json; charset=utf-8",
                    "User-Agent": "okhttp/3.10.0"
                ]
                let (status, data) = try await APIClient.requestRaw(executeURL, method: "POST", headers: headers, body: bodyData)
                let text = String(data: data, encoding: .utf8) ?? ""
                let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
                let code = dict["code"].map { "\($0)" } ?? "-"
                ok = dict.bool("success") == true
                lastMessage = dict.string("msg") ?? dict.string("message") ?? (ok ? "指令已发送" : "车辆未接受指令")
                lastCode = code
                lastRaw = String(text.prefix(100))
                attemptLog += "\(candidate.label)/\(car.carId.suffix(6))=\(code);"
                if ok { break outer }
                if code != "40001" { break }
            }
        }
        if !ok {
            let carIds = cars.map { $0.carId }.joined(separator: ",")
            diag += "cars=\(carIds); tries=\(attemptLog) "
            lastMessage = "\(lastMessage) [code=\(lastCode) \(diag)raw=\(lastRaw)]"
        }
        return CommandResult(ok: ok, message: lastMessage)
    }
}
