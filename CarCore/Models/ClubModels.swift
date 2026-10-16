import Foundation

/// 圈子（玩车社区）数据模型。
/// 字段名同样做了兼容解析，避免服务端调整个别字段导致整个列表空白。
public struct ClubPost: Sendable, Identifiable {
    public let id: String
    public let nick: String
    public let avatar: String
    public let type: String
    public let content: String
    public let images: [String]
    public let likeCount: Int
    public let likedByMe: Bool
    public let commentCount: Int
    public let timeText: String
    public let maskedPhone: String

    public init(id: String, nick: String, avatar: String, type: String, content: String,
                images: [String], likeCount: Int, likedByMe: Bool, commentCount: Int,
                timeText: String, maskedPhone: String) {
        self.id = id
        self.nick = nick
        self.avatar = avatar
        self.type = type
        self.content = content
        self.images = images
        self.likeCount = likeCount
        self.likedByMe = likedByMe
        self.commentCount = commentCount
        self.timeText = timeText
        self.maskedPhone = maskedPhone
    }

    public var typeName: String {
        switch type {
        case "trip": return "用车心得"
        case "bug": return "Bug反馈"
        case "suggest": return "改进建议"
        default: return "动态"
        }
    }

    /// 从 /api/club/list 的 items 数组中解析
    public static func parse(from array: [Any]) -> [ClubPost] {
        array.compactMap { item in
            guard let d = item as? [String: Any] else { return nil }
            let id = d.string("id") ?? d.string("_id") ?? d.string("post_id") ?? UUID().uuidString
            let images = (d["images"] as? [String])
                ?? (d["images"] as? [Any])?.compactMap { $0 as? String }
                ?? (d["imgs"] as? [String])
                ?? []
            return ClubPost(
                id: id,
                nick: d.string("nick") ?? d.string("nickname") ?? d.string("name") ?? "车友",
                avatar: d.string("avatar") ?? d.string("avatar_url") ?? "",
                type: d.string("type") ?? "trip",
                content: d.string("content") ?? d.string("text") ?? d.string("body") ?? "",
                images: images,
                likeCount: d.int("likes") ?? d.int("like_count") ?? d.int("likeCount") ?? 0,
                likedByMe: d.bool("liked") ?? d.bool("liked_by_me") ?? false,
                commentCount: d.int("comments") ?? d.int("comment_count") ?? d.int("commentCount") ?? 0,
                timeText: d.string("time") ?? d.string("timeText") ?? d.string("created_at") ?? d.string("date") ?? "",
                maskedPhone: d.string("phone_masked") ?? d.string("mask") ?? ""
            )
        }
    }
}

/// 圈子列表页整体返回
public struct ClubFeed: Sendable {
    public let posts: [ClubPost]
    public let maskedPhone: String
    public let profileNick: String
    public let profileAvatar: String

    public init(posts: [ClubPost], maskedPhone: String, profileNick: String, profileAvatar: String) {
        self.posts = posts
        self.maskedPhone = maskedPhone
        self.profileNick = profileNick
        self.profileAvatar = profileAvatar
    }

    public static func parse(jsonObject: Any) -> ClubFeed? {
        guard let d = jsonObject as? [String: Any] else { return nil }
        let items = (d["items"] as? [Any]) ?? (d["list"] as? [Any]) ?? (d["posts"] as? [Any]) ?? []
        let profile = d["profile"] as? [String: Any]
        return ClubFeed(
            posts: ClubPost.parse(from: items),
            maskedPhone: d.string("mask") ?? "",
            profileNick: profile?.string("nick") ?? "",
            profileAvatar: profile?.string("avatar") ?? ""
        )
    }
}

/// 圈子评论
public struct ClubComment: Sendable, Identifiable {
    public let id: String
    public let nick: String
    public let content: String
    public let timeText: String

    public init(id: String, nick: String, content: String, timeText: String) {
        self.id = id
        self.nick = nick
        self.content = content
        self.timeText = timeText
    }
}
