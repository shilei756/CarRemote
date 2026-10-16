import Foundation

/// 控车操作历史记录
public struct ControlActionRecord: Sendable, Equatable, Identifiable {
    public var id: String { "\(createAt)-\(cmdDescription)" }
    public let cmdDescription: String
    /// "Completed" 成功 / "RunFailure" 失败
    public let handleStatus: String
    public let resultDesc: String
    public let createAt: String

    public init(cmdDescription: String, handleStatus: String, resultDesc: String, createAt: String) {
        self.cmdDescription = cmdDescription
        self.handleStatus = handleStatus
        self.resultDesc = resultDesc
        self.createAt = createAt
    }

    public var statusText: String {
        switch handleStatus {
        case "Completed": return "成功"
        case "RunFailure": return "失败"
        default: return handleStatus.isEmpty ? "未知" : handleStatus
        }
    }

    public var isSuccess: Bool { handleStatus == "Completed" }
}

/// 消息记录
public struct MessageRecord: Sendable, Equatable, Identifiable {
    public var id: String { "\(msgTime)-\(msgContent)" }
    public let msgTime: String
    public let msgContent: String
    public let typeName: String

    public init(msgTime: String, msgContent: String, typeName: String) {
        self.msgTime = msgTime
        self.msgContent = msgContent
        self.typeName = typeName
    }
}

/// 行程记录
public struct TripRecord: Sendable, Equatable, Identifiable {
    public var id: String { "\(startTime)-\(endTime)" }
    public let startTime: String
    public let endTime: String
    public let startAddress: String
    public let endAddress: String
    public let mileage: Double?
    public let spendTime: Double?
    public let avgSpeed: Double?
    public let oil: Double?

    public init(startTime: String, endTime: String, startAddress: String, endAddress: String,
                mileage: Double?, spendTime: Double?, avgSpeed: Double?, oil: Double?) {
        self.startTime = startTime
        self.endTime = endTime
        self.startAddress = startAddress
        self.endAddress = endAddress
        self.mileage = mileage
        self.spendTime = spendTime
        self.avgSpeed = avgSpeed
        self.oil = oil
    }
}

/// 操作历史 / 消息记录 / 我的行程（与网页版更多功能一致，直连车联网接口）
public enum HistoryService {

    /// 控车操作历史（最近 20 条）
    public static func controlActions(carId: String, accessToken: String) async throws -> [ControlActionRecord] {
        guard var components = URLComponents(string: "https://m.iov.changan.com.cn/appserver/api/car/getControlActionHistory") else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "carId", value: carId),
            URLQueryItem(name: "pageSize", value: "20"),
            URLQueryItem(name: "page", value: "0"),
            URLQueryItem(name: "toast", value: "false"),
            URLQueryItem(name: "ErrorAutoProjectile", value: "false"),
            URLQueryItem(name: "token", value: accessToken),
            URLQueryItem(name: "isNev", value: "0")
        ]
        let object = try await APIClient.request(components.url!, method: "POST", headers: APIClient.changanHeaders)
        guard let dict = object as? [String: Any], dict.bool("success") == true,
              let data = dict["data"] as? [String: Any],
              let array = data["data"] as? [[String: Any]] else { return [] }
        return array.map { item in
            ControlActionRecord(
                cmdDescription: item.string("cmdDescription") ?? "未知操作",
                handleStatus: item.string("handleStatus") ?? "",
                resultDesc: item.string("resultDesc") ?? "",
                createAt: item.string("createAt") ?? item.string("cmdSendTime") ?? ""
            )
        }
    }

    /// 消息记录（最近 30 天，最多 10 条）
    public static func messages(carId: String, accessToken: String) async throws -> [MessageRecord] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd+HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let now = Date()
        let monthAgo = now.addingTimeInterval(-30 * 24 * 3600)
        guard var components = URLComponents(string: "https://m.iov.changan.com.cn/appserver/api/information/pageReceiverInfo") else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "startTime", value: formatter.string(from: monthAgo)),
            URLQueryItem(name: "endTime", value: formatter.string(from: now)),
            URLQueryItem(name: "actionType", value: "1"),
            URLQueryItem(name: "trunkFullPath", value: "APP-CONTROL"),
            URLQueryItem(name: "token", value: accessToken),
            URLQueryItem(name: "isNev", value: "0"),
            URLQueryItem(name: "deviceId", value: "00000000-5768-bcb8-ffff-ffffef05ac4a")
        ]
        let object = try await APIClient.request(components.url!, method: "POST", headers: APIClient.changanHeaders)
        guard let dict = object as? [String: Any] else { return [] }
        guard dict.bool("success") == true || dict.int("status_code") == 0 || dict.int("code") == 0,
              let data = dict["data"] as? [String: Any],
              let array = data["content"] as? [[String: Any]] else { return [] }
        return array.prefix(10).map { item in
            MessageRecord(
                msgTime: item.string("msgTime") ?? item.string("createdAt") ?? "",
                msgContent: item.string("msgContent") ?? item.string("content") ?? "--",
                typeName: item.string("typeName") ?? item.string("infoTypeName") ?? item.string("title") ?? ""
            )
        }
    }

    /// 我的行程（默认近 7 天）
    public static func trips(carId: String, accessToken: String, startDate: String, endDate: String) async throws -> [TripRecord] {
        guard var components = URLComponents(string: APIConfig.iovBaseURL + "/driving") else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "carId", value: carId),
            URLQueryItem(name: "startDate", value: startDate),
            URLQueryItem(name: "endDate", value: endDate),
            URLQueryItem(name: "toast", value: "false"),
            URLQueryItem(name: "token", value: accessToken),
            URLQueryItem(name: "isNev", value: "0"),
            URLQueryItem(name: "deviceId", value: "00000000-5768-bcb8-ffff-ffffef05ac4a")
        ]
        let object = try await APIClient.getJSON(components.url!, headers: APIClient.changanHeaders)
        guard let dict = object as? [String: Any],
              dict.bool("success") == true || dict.int("status_code") == 0 || dict.int("code") == 0,
              let array = dict["data"] as? [[String: Any]] else { return [] }
        return array.reversed().map { item in
            TripRecord(
                startTime: item.string("startTime") ?? "--",
                endTime: item.string("endTime") ?? "--",
                startAddress: item.string("startAddressName") ?? "--",
                endAddress: item.string("endAddressName") ?? "--",
                mileage: item.double("mileage"),
                spendTime: item.double("spendTime"),
                avgSpeed: item.double("avrgSpeed"),
                oil: item.double("oil")
            )
        }
    }
}
