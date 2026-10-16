import Foundation

/// 圈子（玩车社区）服务
public enum ClubService {

    /// 加载动态列表
    public static func list(credentials: Credentials) async throws -> ClubFeed {
        guard let url = URL(string: APIConfig.siteBaseURL + "/api/club/list") else {
            throw APIError.invalidURL
        }
        let object = try await APIClient.postJSON(url, json: [
            "phone": credentials.phone,
            "pin": credentials.pin
        ])
        guard let dict = object as? [String: Any], dict.bool("success") == true else {
            let message = (object as? [String: Any])?.string("message") ?? "加载失败"
            throw APIError.server(message)
        }
        guard let feed = ClubFeed.parse(jsonObject: dict) else {
            throw APIError.decode("内容解析失败")
        }
        return feed
    }

    /// 发布动态
    public static func post(credentials: Credentials, type: String, nick: String,
                            avatar: String, images: [String], content: String) async throws {
        guard let url = URL(string: APIConfig.siteBaseURL + "/api/club/post") else {
            throw APIError.invalidURL
        }
        let object = try await APIClient.postJSON(url, json: [
            "phone": credentials.phone,
            "pin": credentials.pin,
            "type": type,
            "nick": nick,
            "avatar": avatar,
            "images": images,
            "content": content
        ])
        guard let dict = object as? [String: Any], dict.bool("success") == true else {
            let message = (object as? [String: Any])?.string("message") ?? "发布失败"
            throw APIError.server(message)
        }
    }

    /// 点赞 / 取消点赞
    public static func like(credentials: Credentials, postId: String) async throws -> Bool {
        guard let url = URL(string: APIConfig.siteBaseURL + "/api/club/like") else {
            throw APIError.invalidURL
        }
        let object = try await APIClient.postJSON(url, json: [
            "phone": credentials.phone,
            "pin": credentials.pin,
            "id": postId
        ])
        guard let dict = object as? [String: Any], dict.bool("success") == true else {
            let message = (object as? [String: Any])?.string("message") ?? "操作失败"
            throw APIError.server(message)
        }
        return dict.bool("liked") ?? true
    }

    /// 发表评论
    public static func comment(credentials: Credentials, postId: String, content: String) async throws {
        guard let url = URL(string: APIConfig.siteBaseURL + "/api/club/comment") else {
            throw APIError.invalidURL
        }
        let object = try await APIClient.postJSON(url, json: [
            "phone": credentials.phone,
            "pin": credentials.pin,
            "id": postId,
            "content": content
        ])
        guard let dict = object as? [String: Any], dict.bool("success") == true else {
            let message = (object as? [String: Any])?.string("message") ?? "评论失败"
            throw APIError.server(message)
        }
    }

    /// 上传图片，返回可用的 URL
    public static func uploadImage(credentials: Credentials, data: Data,
                                   fileName: String = "photo.jpg") async throws -> String {
        guard let url = URL(string: APIConfig.siteBaseURL + "/api/club/upload") else {
            throw APIError.invalidURL
        }
        let object = try await APIClient.upload(
            url,
            fileField: "file",
            fileName: fileName,
            mimeType: "image/jpeg",
            fileData: data,
            extraFields: [
                ("phone", credentials.phone),
                ("pin", credentials.pin)
            ]
        )
        guard let dict = object as? [String: Any], dict.bool("success") == true,
              let uploaded = dict.string("url") ?? dict.string("path") ?? dict.string("link"),
              !uploaded.isEmpty else {
            let message = (object as? [String: Any])?.string("message") ?? "上传失败"
            throw APIError.server(message)
        }
        // 兼容相对路径
        if uploaded.hasPrefix("http") { return uploaded }
        return APIConfig.siteBaseURL + (uploaded.hasPrefix("/") ? uploaded : "/" + uploaded)
    }
}
