import Foundation
import CarCore
import UIKit

/// 圈子（玩车社区）视图模型：动态流 / 点赞 / 评论 / 发布
@MainActor
final class ClubViewModel: ObservableObject {

    @Published var posts: [ClubPost] = []
    @Published var maskedPhone: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var likedPostIDs: Set<String> = []

    /// 发布相关
    @Published var showPublish = false
    @Published var publishType: ClubPostType = .trip
    @Published var publishContent: String = ""
    @Published var pickedImages: [UIImage] = []
    @Published var isPublishing = false
    @Published var publishError: String?

    /// 评论相关
    @Published var commentingPost: ClubPost?
    @Published var commentText: String = ""
    @Published var isCommenting = false

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    var credentials: Credentials? { appState?.credentials }

    // MARK: - 列表

    func load() async {
        guard let credentials, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let feed = try await ClubService.list(credentials: credentials)
            posts = feed.posts
            maskedPhone = feed.maskedPhone
            likedPostIDs = Set(feed.posts.filter(\.likedByMe).map(\.id))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 点赞

    func toggleLike(_ post: ClubPost) {
        guard let credentials else { return }
        let wasLiked = likedPostIDs.contains(post.id)
        // 乐观更新
        if wasLiked {
            likedPostIDs.remove(post.id)
        } else {
            likedPostIDs.insert(post.id)
        }
        updateLikeCount(for: post.id, liked: !wasLiked)
        Task {
            do {
                let liked = try await ClubService.like(credentials: credentials, postId: post.id)
                if liked == likedPostIDs.contains(post.id) { return }
                if liked {
                    likedPostIDs.insert(post.id)
                } else {
                    likedPostIDs.remove(post.id)
                }
                updateLikeCount(for: post.id, liked: liked)
            } catch {
                // 回滚
                if wasLiked {
                    likedPostIDs.insert(post.id)
                } else {
                    likedPostIDs.remove(post.id)
                }
                updateLikeCount(for: post.id, liked: wasLiked)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func updateLikeCount(for postID: String, liked: Bool) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        let old = posts[index]
        posts[index] = ClubPost(
            id: old.id, nick: old.nick, avatar: old.avatar, type: old.type,
            content: old.content, images: old.images,
            likeCount: max(0, old.likeCount + (liked ? 1 : -1)),
            likedByMe: liked, commentCount: old.commentCount,
            timeText: old.timeText, maskedPhone: old.maskedPhone
        )
    }

    // MARK: - 发布

    var canPublish: Bool {
        !publishContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isPublishing
    }

    func publish() async {
        guard let credentials, canPublish else { return }
        isPublishing = true
        publishError = nil
        defer { isPublishing = false }
        do {
            var imageURLs: [String] = []
            for (index, image) in pickedImages.enumerated() {
                guard let data = image.jpegData(compressionQuality: 0.82) else { continue }
                let url = try await ClubService.uploadImage(
                    credentials: credentials,
                    data: data,
                    fileName: "club-\(Int(Date().timeIntervalSince1970))-\(index).jpg"
                )
                imageURLs.append(url)
            }
            let settings = SharedStore.loadSettings()
            try await ClubService.post(
                credentials: credentials,
                type: publishType.rawValue,
                nick: settings.clubNick.isEmpty ? credentials.maskedPhone : settings.clubNick,
                avatar: settings.clubAvatar,
                images: imageURLs,
                content: publishContent.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            publishContent = ""
            pickedImages = []
            showPublish = false
            await load()
        } catch {
            publishError = error.localizedDescription
        }
    }

    // MARK: - 评论

    func submitComment() async {
        guard let credentials, let post = commentingPost else { return }
        let content = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isCommenting else { return }
        isCommenting = true
        defer { isCommenting = false }
        do {
            try await ClubService.comment(credentials: credentials, postId: post.id, content: content)
            commentText = ""
            commentingPost = nil
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 圈子动态类型（与网页版一致）
enum ClubPostType: String, CaseIterable {
    case trip = "trip"
    case bug = "bug"
    case suggest = "suggest"

    var displayName: String {
        switch self {
        case .trip: return "用车心得"
        case .bug: return "Bug 反馈"
        case .suggest: return "改进建议"
        }
    }
}
