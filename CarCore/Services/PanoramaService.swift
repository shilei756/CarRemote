import Foundation

/// 360 全景照片条目
public struct PanoramaImage: Sendable {
    public let url: String
    public let name: String

    public init(url: String, name: String) {
        self.url = url
        self.name = name
    }
}

/// 360 全景历史记录（服务端已按 前/左/右/后 排序）
public struct PanoramaRecord: Sendable {
    public let timestamp: Date
    public let dirLabels: [String]
    /// 4 个方位的本地缓存文件名（可能为空 = 图片已失效）
    public let imageFiles: [String]

    public init(timestamp: Date, dirLabels: [String], imageFiles: [String]) {
        self.timestamp = timestamp
        self.dirLabels = dirLabels
        self.imageFiles = imageFiles
    }
}

/// 360 全景服务：下发拍照 → 轮询车端上传 → 取图 → 服务端存档/历史
public enum PanoramaService {

    private static let mediaDeviceId = "ffffffff-eb2a-33b8-ffff-ffffef05ac4a"

    /// 下发远程拍照指令（与网页版 photograph 相同链路），返回 taskId
    public static func request(credentials: Credentials) async throws -> String {
        let result = try await CarService.performAction(action: "photograph", credentials: credentials)
        guard result.ok else {
            throw APIError.server(result.message)
        }
        guard let taskId = result.taskId, !taskId.isEmpty else {
            throw APIError.server("车端未返回拍照任务 ID，请稍后重试")
        }
        return taskId
    }

    /// 按任务 ID 查询车端上传的图片（未上传完成时返回空数组）
    public static func fetchImages(taskId: String, credentials: Credentials) async throws -> [PanoramaImage] {
        let (token, updatedCredentials) = try await AuthService.validAccessToken(for: credentials)
        SharedStore.saveCredentials(updatedCredentials)
        guard var components = URLComponents(string: "https://m.iov.changan.com.cn/appserver/api/file/getMediaFilesByTaskId") else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "taskId", value: taskId),
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "isNev", value: "0"),
            URLQueryItem(name: "deviceId", value: mediaDeviceId)
        ]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        let object = try await APIClient.request(components.url!, method: "POST", headers: APIClient.changanHeaders)
        guard let dict = object as? [String: Any] else {
            throw APIError.decode("全景取图解析失败")
        }
        guard dict.bool("success") == true else {
            throw APIError.server(dict.string("msg") ?? dict.string("message") ?? "取图失败")
        }
        guard let list = dict["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { item in
            guard let url = item.string("url"), !url.isEmpty else { return nil }
            return PanoramaImage(url: url, name: item.string("name") ?? "")
        }
    }

    /// 存档到服务端（写入历史，服务端缓存图片绕跨域）
    public static func save(phone: String, taskId: String, images: [PanoramaImage]) async {
        guard let url = URL(string: APIConfig.siteBaseURL + "/api/panorama/save") else { return }
        let imagesPayload: [[String: String]] = images.map { ["url": $0.url, "name": $0.name] }
        _ = try? await APIClient.postJSON(url, json: [
            "task_id": taskId,
            "phone": phone,
            "images": imagesPayload
        ])
    }

    /// 历史记录（/pano_cache 本地缓存图，带 phone 归属校验）
    public static func history(phone: String, start: String, end: String) async throws -> [PanoramaRecord] {
        guard var components = URLComponents(string: APIConfig.siteBaseURL + "/api/panorama/history") else {
            throw APIError.invalidURL
        }
        components.queryItems = [
            URLQueryItem(name: "phone", value: phone),
            URLQueryItem(name: "start", value: start),
            URLQueryItem(name: "end", value: end)
        ]
        let object = try await APIClient.getJSON(components.url!)
        guard let dict = object as? [String: Any],
              let list = dict["records"] as? [[String: Any]] else { return [] }
        return list.map { rec in
            let ts = rec.double("ts") ?? 0
            let dirs = rec["dirs"] as? [String] ?? []
            let images = rec["images"] as? [String] ?? []
            return PanoramaRecord(
                timestamp: Date(timeIntervalSince1970: ts),
                dirLabels: dirs,
                imageFiles: images
            )
        }
    }

    /// Unix 秒 → "yyyy-MM-dd HH:mm"
    public static func formattedTime(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        f.timeZone = .current
        return f.string(from: date)
    }

    /// 历史缓存图地址：/pano_cache/<file>?phone=
    public static func cacheURL(file: String, phone: String) -> URL? {
        guard var components = URLComponents(string: APIConfig.siteBaseURL + "/pano_cache/" + file) else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "phone", value: phone)]
        return components.url
    }

    /// 新拍远程图代理地址（绕跨域保存）：/panorama_image?url=&name=
    public static func proxyURL(for remoteURL: String, name: String) -> URL? {
        guard var components = URLComponents(string: APIConfig.siteBaseURL + "/panorama_image") else {
            return nil
        }
        components.queryItems = [
            URLQueryItem(name: "url", value: remoteURL),
            URLQueryItem(name: "name", value: name)
        ]
        return components.url
    }
}
