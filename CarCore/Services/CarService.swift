import Foundation

/// 车辆位置详情（car/location 接口，含官网返回的具体地址）
public struct CarLocationInfo: Sendable, Equatable {
    public let address: String
    public let city: String
    public let latitude: Double
    public let longitude: Double
    public let gpsTime: String
    public let speed: Double?

    public init(address: String, city: String, latitude: Double, longitude: Double, gpsTime: String, speed: Double?) {
        self.address = address
        self.city = city
        self.latitude = latitude
        self.longitude = longitude
        self.gpsTime = gpsTime
        self.speed = speed
    }
}

/// 车辆数据与控车指令服务。
///
/// 指令下发链路（与网页版完全一致）：
/// 1. 初始化 PIN 校验 → 2. 获取安全公钥 → 3. 站内加密代理 → 4. 车联网执行。
public enum CarService {

    /// 获取账号绑定车辆列表
    public static func fetchCars(accessToken: String) async throws -> [CarInfo] {
        guard var components = URLComponents(string: APIConfig.iovBaseURL + "/user/cars") else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "type", value: "0"),
            URLQueryItem(name: "token", value: accessToken)
        ]
        let object = try await APIClient.getJSON(components.url!, headers: APIClient.changanHeaders)
        guard let dict = object as? [String: Any] else { throw APIError.decode("车辆列表解析失败") }
        if let array = dict["data"] as? [Any] {
            let cars = CarInfo.parse(from: array)
            if !cars.isEmpty { return cars }
        }
        if let array = object as? [Any] {
            let cars = CarInfo.parse(from: array)
            if !cars.isEmpty { return cars }
        }
        return []
    }

    /// 获取整车车况（keys=* 全量字段）
    public static func fetchStatus(carId: String, accessToken: String) async throws -> CarStatus {
        guard var components = URLComponents(string: APIConfig.iovBaseURL + "/car/data") else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "carId", value: carId),
            URLQueryItem(name: "ErrorAutoProjectile", value: "false"),
            URLQueryItem(name: "toast", value: "false"),
            URLQueryItem(name: "keys", value: "*"),
            URLQueryItem(name: "isNev", value: "0"),
            URLQueryItem(name: "token", value: accessToken)
        ]
        let object = try await APIClient.postForm(components.url!, params: [], headers: APIClient.changanHeaders)
        guard let dict = object as? [String: Any] else { throw APIError.decode("车况解析失败") }
        guard let data = dict["data"] as? [String: Any] else {
            throw APIError.server(dict.string("message") ?? dict.string("msg") ?? "未获取到车况数据")
        }
        return CarStatus(raw: data)
    }

    /// 一键刷新：自动处理 token 与车辆选择
    public static func refresh(credentials: Credentials) async throws -> (status: CarStatus, car: CarInfo, credentials: Credentials) {
        let (token, updatedCredentials) = try await AuthService.validAccessToken(for: credentials)
        let cars = try await fetchCars(accessToken: token)
        guard let car = cars.first else {
            throw APIError.server("未获取到车辆信息，请确认账号已绑定车辆")
        }
        let status = try await fetchStatus(carId: car.carId, accessToken: token)
        return (status, car, updatedCredentials)
    }

    /// 获取车辆实时位置（与网页版位置卡一致：官网返回 address 具体地址）
    public static func fetchLocation(carId: String, accessToken: String) async throws -> CarLocationInfo {
        guard var components = URLComponents(string: APIConfig.iovBaseURL + "/car/location") else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "carId", value: carId),
            URLQueryItem(name: "mapType", value: "GCJ02"),
            URLQueryItem(name: "ErrorAutoProjectile", value: "false"),
            URLQueryItem(name: "toast", value: "false"),
            URLQueryItem(name: "token", value: accessToken),
            URLQueryItem(name: "isNev", value: "0"),
            URLQueryItem(name: "deviceId", value: "00000000-5768-bcb8-ffff-ffffef05ac4a")
        ]
        let object = try await APIClient.getJSON(components.url!, headers: APIClient.changanHeaders)
        guard let dict = object as? [String: Any] else { throw APIError.decode("位置解析失败") }
        guard let data = dict["data"] as? [String: Any] else {
            throw APIError.server(dict.string("message") ?? dict.string("msg") ?? "未获取到位置数据")
        }
        let lat = data.double("lat") ?? data.double("latitude") ?? 0
        let lng = data.double("lng") ?? data.double("longitude") ?? 0
        return CarLocationInfo(
            address: data.string("address") ?? "",
            city: data.string("city") ?? "",
            latitude: lat,
            longitude: lng,
            gpsTime: data.string("gpsTime") ?? "",
            speed: data.double("speed")
        )
    }

    /// 执行控车指令
    public static func execute(command: CarCommand, credentials: Credentials) async throws -> CommandResult {
        try await performAction(action: command.rawValue, credentials: credentials)
    }

    /// 通用指令下发（含 360 全景 photograph），复用 PIN 校验 → 公钥 → 加密 → execute 链路
    public static func performAction(action: String, credentials: Credentials) async throws -> CommandResult {
        let (token, updatedCredentials) = try await AuthService.validAccessToken(for: credentials)
        SharedStore.saveCredentials(updatedCredentials)

        let cars = try await fetchCars(accessToken: token)
        guard let car = cars.first else {
            throw APIError.server("未获取到车辆信息")
        }

        // 1. 初始化 PIN 校验
        guard let pinVerifyURL = URL(string: APIConfig.iovBaseURL + "/control/createPinVerifyCode") else {
            throw APIError.invalidURL
        }
        let pinObject = try await APIClient.postForm(
            pinVerifyURL,
            params: [("token", token)],
            headers: APIClient.changanHeaders
        )
        guard let pinDict = pinObject as? [String: Any],
              let pinVerifyCode = pinDict.string("data"), !pinVerifyCode.isEmpty else {
            throw APIError.server("PIN 校验初始化失败")
        }

        // 2. 获取安全公钥
        guard var keyComponents = URLComponents(string: APIConfig.iovBaseURL + "/v2/security/key") else {
            throw APIError.invalidURL
        }
        keyComponents.queryItems = [
            URLQueryItem(name: "carId", value: car.carId),
            URLQueryItem(name: "token", value: token)
        ]
        let keyObject = try await APIClient.getJSON(keyComponents.url!, headers: APIClient.changanHeaders)
        guard let keyDict = keyObject as? [String: Any],
              let publicKey = keyDict.string("data"), !publicKey.isEmpty else {
            throw APIError.server("安全密钥获取失败")
        }

        // 3. 站内加密代理（RSA 在服务端完成）
        guard let encryptURL = URL(string: APIConfig.siteBaseURL + "/encrypt_data") else {
            throw APIError.invalidURL
        }
        let plaintextObject: [String: Any] = [
            "pinVerifyCode": pinVerifyCode,
            "cmd": action,
            "type": action,
            "pin": credentials.pin,
            "wifiPassword": ""
        ]
        let plaintextData = try JSONSerialization.data(withJSONObject: plaintextObject)
        let encryptObject = try await APIClient.postJSON(encryptURL, json: [
            "phone": credentials.phone,
            "public_key": publicKey,
            "plaintext": String(data: plaintextData, encoding: .utf8) ?? ""
        ])
        guard let encryptDict = encryptObject as? [String: Any],
              encryptDict.bool("success") == true,
              let encrypted = encryptDict.string("encrypted_data"), !encrypted.isEmpty else {
            let message = (encryptObject as? [String: Any])?.string("error")
                ?? (encryptObject as? [String: Any])?.string("message")
                ?? "指令加密失败"
            throw APIError.server(message)
        }

        // 4. 下发指令
        guard let executeURL = URL(string: APIConfig.iovBaseURL + "/v3/control/execute") else {
            throw APIError.invalidURL
        }
        let executeObject = try await APIClient.postForm(
            executeURL,
            params: [
                ("toast", "false"),
                ("phoneType", "a"),
                ("s", encrypted),
                ("phoneId", "b"),
                ("isNev", "0"),
                ("temperature", "0"),
                ("loading", "false"),
                ("carId", car.carId),
                ("token", token)
            ],
            headers: APIClient.changanHeaders
        )
        let dict = executeObject as? [String: Any] ?? [:]
        let ok = dict.bool("success") == true || dict.int("code") == 200 || dict.string("code") == "200"
        let message = dict.string("msg") ?? dict.string("message")
            ?? (ok ? "指令已发送到车机" : "车辆未接受指令")
        // 360 全景等异步任务：解析 data.taskId 供后续轮询取图
        let taskId = (dict["data"] as? [String: Any])?.string("taskId")
        return CommandResult(ok: ok, message: message, taskId: taskId)
    }
}
