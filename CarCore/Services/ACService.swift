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

    // MARK: - 通道判定（CAKOCHE 恒走新版，正式版沿用用户设置）

    /// 空调指令是否走「新版空调通道」（网页版 newAC / 长安开放平台）。
    ///
    /// CAKOCHE 及其点阵小组件、快捷指令**恒定走新版通道**，授权一律来自站主网站
    /// （`/api/open/token` 直接取网站凭证，`/api/ac/*` 走网站扫码开通），
    /// 不读 `acMode` 开关，避免与正式版共用的 App Group 设置互相串扰。
    ///
    /// CarCore 是共享 framework，编译时没有 `CAKOCHE` 宏，因此用 bundle id 运行时判定：
    /// 正式版为 `app.copper1249.chipmunk6639*`，不匹配前缀 → 回落原有
    /// `SharedStore.loadACMode()`，正式版行为零变化。
    public static func useNewChannel() -> Bool {
        let bundleID = Bundle.main.bundleIdentifier ?? ""
        if bundleID.hasPrefix("app.copper1249.cakoche") { return true }
        return SharedStore.loadACMode() == .new
    }

    /// 是否 CAKOCHE 体系（主 App / 点阵小组件 / 快捷指令）。
    public static var isCakoche: Bool {
        (Bundle.main.bundleIdentifier ?? "").hasPrefix("app.copper1249.cakoche")
    }

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

    // MARK: - 网站授权通道（CAKOCHE 空调授权统一入口）

    /// 直接调用站主网站的授权通道：用登录态授权码向站内 `/api/open/token`
    /// 换取网站为该账号保存的开放平台 `refresh_token`，落盘供后续空调指令使用。
    ///
    /// 与扫码开通（`/api/ac/qrcode` + `/api/ac/status`）互为两条授权路径：
    /// 网站侧已开通过 → 本方法一次调用即可同步；未开通过 → 走扫码开通页。
    /// 二者都由网站统一判定，App 不自建授权体系。
    /// - Returns: (是否成功, 面向用户的说明文案)
    public static func syncWebsiteAuthorization(credentials: Credentials) async -> (ok: Bool, message: String) {
        let authorizeToken: String
        do {
            let valid = try await AuthService.validAccessToken(for: credentials)
            authorizeToken = valid.token
            SharedStore.saveCredentials(valid.credentials)
        } catch {
            return (false, "无法获取登录态：\(error.localizedDescription)")
        }

        guard let url = URL(string: APIConfig.siteBaseURL + "/api/open/token") else {
            return (false, "授权地址无效")
        }
        let object: Any
        do {
            object = try await APIClient.postJSON(url, json: [
                "phone": credentials.phone,
                "authorize_token": authorizeToken
            ])
        } catch {
            return (false, "无法连接网站授权服务：\(error.localizedDescription)")
        }
        guard let dict = object as? [String: Any] else {
            return (false, "网站授权响应异常")
        }
        guard dict.bool("success") == true,
              let refreshToken = dict.string("refresh_token"), !refreshToken.isEmpty else {
            let hint = dict.string("message") ?? "该账号尚未在网站开通新版空调授权，请先扫码开通"
            return (false, hint)
        }

        // 网站已授权：先落盘最新 refresh_token，再刷新一次以确认车控权限并更新到期时间。
        SharedStore.saveACOpenRefreshToken(refreshToken)
        do {
            let (_, rotated, _) = try await renewOpenToken(refreshToken)
            if let rotated, !rotated.isEmpty {
                SharedStore.saveACOpenRefreshToken(rotated)
            }
            let days = SharedStore.loadACActivationExpire().map {
                max(0, Int($0.timeIntervalSinceNow / 86400))
            }
            return (true, days.map { "已同步网站授权 · 剩余 \($0) 天" } ?? "已同步网站授权")
        } catch {
            // 凭证已存下，指令下发时 executeOfficial 仍会走完整候选链路重试
            return (true, "已同步网站授权（校验稍后自动完成）")
        }
    }

    /// 当前网站授权状态文案（优先本地到期缓存，避免每次打开都走完整链路）
    public static func websiteAuthorizationText() -> String {
        guard let expire = SharedStore.loadACActivationExpire(), expire > Date() else {
            return "未开通 / 未同步"
        }
        return "已授权 · 剩余 \(max(0, Int(expire.timeIntervalSinceNow / 86400))) 天"
    }

    // MARK: - 开放平台令牌刷新（与网页版一致，可复用）

    /// 用 refresh_token 向长安开放平台换取 access_token，并自动保存轮换后的新 refresh_token。
    /// 抽出为静态方法，供空调指令下发与「到期自动续期」共用。
    public static func renewOpenToken(_ refreshToken: String) async throws -> (accessToken: String, newRefreshToken: String?, scope: String?) {
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
        // 关键：oauth 刷新会轮换 refresh_token，旧的立即作废（再刷只会拿到降级 token）。
        // 必须把最新的存回本地，否则下次刷新失败。
        let rotated = oauthDict.string("refresh_token")
        if let rotated, !rotated.isEmpty {
            SharedStore.saveACOpenRefreshToken(rotated)
        }
        // oauth 响应带新 refresh_token 的有效期：顺手刷新「新版授权剩余」缓存。
        // 这样自动续期后界面立刻显示新的到期天数，避免缓存一直是旧值。
        if let expireIn = oauthDict.int("refresh_token_expire_in") {
            SharedStore.saveACActivationExpire(Date().addingTimeInterval(TimeInterval(expireIn)))
        }
        return (token, rotated, oauthDict.string("scope"))
    }

    // MARK: - 到期自动续期（#4：免去用户手动扫码）

    /// 新版空调到期自动续期：当授权临近到期（≤ thresholdDays 天）时，主动用本地
    /// refresh_token 轮换延长，用户无需再手动扫码。仅当本地已有 refresh_token 时尝试，
    /// 令牌彻底失效才回退到「扫码开通」。建议在 App 进入前台时调用。
    public static func tryAutoRenew(credentials: Credentials, thresholdDays: Int = 7) async {
        // 1. 先看剩余天数（内部优先用本地到期缓存，避免每次走完整链路）
        let remaining = await activationRemainingDays(credentials: credentials)
        // 余量充足：无需续期
        guard let remaining, remaining <= thresholdDays else { return }
        // 2. 仅当本地已存有 refresh_token（曾经开通过）才尝试自动续期
        guard let refreshToken = SharedStore.loadACOpenRefreshToken() else { return }
        do {
            // 3. 主动轮换。renewOpenToken 内部会用 oauth 响应的
            //    refresh_token_expire_in 刷新本地到期缓存，界面「授权剩余」随即更新，
            //    无需再走一次完整链路（旧实现重复调用会命中旧缓存，天数永不变化）。
            _ = try await renewOpenToken(refreshToken)
        } catch {
            // 续期失败（令牌已失效等）：清掉本地 token，回退到扫码开通流程
            SharedStore.saveACOpenRefreshToken(nil)
        }
    }

    /// 通过长安开放平台执行空调指令（网页版 newAC）
    /// - Parameters:
    ///   - temperature: 开空调目标温度（16~32，网页版调温弹窗随指令下发；nil 时不下发温度）
    public static func executeOfficial(command: CarCommand, credentials: Credentials, temperature: Int? = nil) async throws -> CommandResult {
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
        //    （oauth 刷新逻辑已抽为静态方法 renewOpenToken，见上方「到期自动续期」区）

        var tokenCandidates: [(label: String, token: String)] = []

        // A0. 本地最新轮换 token（自己上次刷新存下的，最新鲜、优先）
        if let localRT = SharedStore.loadACOpenRefreshToken() {
            do {
                let (token, _, scope) = try await renewOpenToken(localRT)
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
                let (token, _, scope) = try await renewOpenToken(rt)
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
                let (token, _, scope) = try await renewOpenToken(rt)
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
                // mapArgsJson：开空调带目标温度（网页版 confirmAcTemp：{"temperature":"24"}），其余为空
                let mapArgs: String
                if command == .openAir, let temperature, (16...32).contains(temperature) {
                    mapArgs = (try? JSONSerialization.data(withJSONObject: ["temperature": String(temperature)]))
                        .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
                } else {
                    mapArgs = "{}"
                }
                let body: [String: Any] = [
                    "mapArgsJson": mapArgs,
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
