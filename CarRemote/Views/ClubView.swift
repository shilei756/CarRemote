import SwiftUI
import PhotosUI
import UIKit
import CarCore

/// 圈子（玩车社区）——照搬网页版 clubPage：页面内嵌发布卡 + 白卡帖子列表
struct ClubView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: ClubViewModel

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: ClubViewModel(appState: appState))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let errorMessage = viewModel.errorMessage {
                        infoBanner(errorMessage, color: WebTheme.red)
                    }

                    // 网页版发布卡（内嵌页面顶部，而非弹窗）
                    PublishCard(viewModel: viewModel)

                    // 帖子列表（网页版 clubList space-y-3）
                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        ProgressView()
                            .tint(WebTheme.blue)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if viewModel.posts.isEmpty {
                        EmptyStateView(
                            systemImage: "bubble.left.and.bubble.right",
                            title: "还没有动态",
                            message: "在上面发布第一条用车心得吧"
                        )
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.posts) { post in
                                PostCard(
                                    post: post,
                                    isLiked: viewModel.likedPostIDs.contains(post.id),
                                    onLike: { viewModel.toggleLike(post) },
                                    onComment: { viewModel.commentingPost = post }
                                )
                            }
                        }
                    }
                    Spacer(minLength: 32)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(WebConsoleBackground())
            .navigationTitle("玩车圈子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // 网页版 clubMeChip：右侧显示我的昵称
                ToolbarItem(placement: .topBarTrailing) {
                    Text(SharedStore.loadSettings().clubNick.isEmpty ? "车友" : SharedStore.loadSettings().clubNick)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WebTheme.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(WebTheme.blue.opacity(0.10))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .refreshable {
                await viewModel.load()
            }
            .task {
                await viewModel.load()
            }
            .sheet(item: $viewModel.commentingPost) { post in
                CommentSheet(viewModel: viewModel, post: post)
            }
        }
    }

    private func infoBanner(_ message: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(color)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.muted)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 网页版内嵌发布卡：分类三按钮 + 输入框 + 图片 + 渐变发布按钮
struct PublishCard: View {
    @ObservedObject var viewModel: ClubViewModel
    @State private var selectedItems: [PhotosPickerItem] = []
    @FocusState private var inputFocused: Bool

    var body: some View {
        SectionCard(sakura: false) {
            VStack(alignment: .leading, spacing: 10) {
                // 分类三按钮（网页版 flex gap-2）
                HStack(spacing: 8) {
                    ForEach(ClubPostType.allCases, id: \.self) { type in
                        Button {
                            viewModel.publishType = type
                        } label: {
                            Text(type.displayName)
                                .font(.system(size: 12.5, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .foregroundStyle(
                                    viewModel.publishType == type
                                        ? .white
                                        : WebTheme.muted
                                )
                                .background(
                                    viewModel.publishType == type
                                        ? WebTheme.navGradient
                                        : LinearGradient(colors: [WebTheme.card2], startPoint: .leading, endPoint: .trailing)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            viewModel.publishType == type ? .clear : WebTheme.border,
                                            lineWidth: 1
                                        )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // 输入行：头像 + textarea（网页版 flex items-center gap-2.5）
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(WebTheme.blue.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(WebTheme.blue)
                    }
                    ZStack(alignment: .topLeading) {
                        if viewModel.publishContent.isEmpty {
                            Text("分享你的用车心得、反馈问题或提出建议…")
                                .font(.system(size: 13))
                                .foregroundStyle(WebTheme.faint)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                        }
                        TextEditor(text: $viewModel.publishContent)
                            .font(.system(size: 13))
                            .foregroundStyle(WebTheme.txt)
                            .tint(WebTheme.blue)
                            .frame(minHeight: 64)
                            .padding(6)
                            .scrollContentBackground(.hidden)
                            .background(WebTheme.card2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .focused($inputFocused)
                    }
                }

                // 已选图片（网页版 clubImgs flex-wrap）
                if !viewModel.pickedImages.isEmpty {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                        spacing: 6
                    ) {
                        ForEach(Array(viewModel.pickedImages.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        viewModel.pickedImages.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 14))
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .offset(x: 5, y: -5)
                                }
                        }
                    }
                }

                // 底部：添加图片 + 字数 + 发布按钮（网页版 flex justify-between）
                HStack {
                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 9,
                        matching: .images
                    ) {
                        HStack(spacing: 4) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 13))
                            Text("图片")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(WebTheme.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(WebTheme.card2)
                        .clipShape(Capsule())
                        .overlay(Capsule().strokeBorder(WebTheme.border, lineWidth: 1))
                    }

                    Spacer()

                    Text("\(viewModel.publishContent.count)/500")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(WebTheme.faint)

                    // 网页版 ctl-on 渐变发布按钮
                    Button {
                        inputFocused = false
                        Task { await viewModel.publish() }
                    } label: {
                        HStack(spacing: 4) {
                            if viewModel.isPublishing {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .tint(.white)
                            } else {
                                Text("发布")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(WebTheme.navGradient)
                        .clipShape(Capsule())
                        .shadow(color: WebTheme.blue.opacity(0.3), radius: 12, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canPublish)
                }

                if let publishError = viewModel.publishError {
                    Text(publishError)
                        .font(.system(size: 11))
                        .foregroundStyle(WebTheme.red)
                }
            }
        }
        .onChange(of: selectedItems) { _, newItems in
            loadImages(from: newItems)
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) {
        Task {
            var images: [UIImage] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            viewModel.pickedImages = images
        }
    }
}

/// 单条动态卡片（网页版帖子卡：白卡 + 头像 + 类型 chip + 图片 + 点赞评论）
struct PostCard: View {
    let post: ClubPost
    let isLiked: Bool
    let onLike: () -> Void
    let onComment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 头部：头像 + 昵称 + 类型 chip + 时间
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(WebTheme.blue.opacity(0.12))
                        .frame(width: 38, height: 38)
                    if !post.avatar.isEmpty, let url = URL(string: post.avatar) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.fill")
                                .foregroundStyle(WebTheme.blue)
                        }
                        .frame(width: 38, height: 38)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(WebTheme.blue)
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(post.nick)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(WebTheme.txt)
                    HStack(spacing: 6) {
                        Text(post.typeName)
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(WebTheme.blue.opacity(0.10))
                            .foregroundStyle(WebTheme.blue)
                            .clipShape(Capsule())
                        if !post.timeText.isEmpty {
                            Text(post.timeText)
                                .font(.system(size: 10.5))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.faint)
                        }
                    }
                }
                Spacer()
            }

            // 正文
            Text(post.content)
                .font(.system(size: 13.5))
                .foregroundStyle(WebTheme.txt)
                .fixedSize(horizontal: false, vertical: true)

            // 图片
            if !post.images.isEmpty {
                TabView {
                    ForEach(post.images, id: \.self) { imageURL in
                        if let url = URL(string: imageURL) {
                            AsyncImage(url: url) { image in
                                image.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle()
                                    .fill(WebTheme.card2)
                                    .overlay(ProgressView().tint(WebTheme.blue))
                            }
                            .frame(height: 200)
                            .clipped()
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // 操作栏
            HStack(spacing: 24) {
                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .font(.system(size: 13))
                            .foregroundStyle(isLiked ? WebTheme.red : WebTheme.muted)
                        Text("\(post.likeCount)")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.muted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isLiked ? "取消点赞" : "点赞")

                Button(action: onComment) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .font(.system(size: 13))
                            .foregroundStyle(WebTheme.muted)
                        Text("\(post.commentCount)")
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.muted)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("评论")

                Spacer()
            }
        }
        .padding(14)
        .webCard()
    }
}

/// 评论（网页版 sheet：backdrop 深色 + 圆角面板）
struct CommentSheet: View {
    @ObservedObject var viewModel: ClubViewModel
    let post: ClubPost
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                ScrollView {
                    Text(post.content)
                        .font(.system(size: 13.5))
                        .foregroundStyle(WebTheme.txt)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(WebTheme.card2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 10) {
                    TextField("写评论…", text: $viewModel.commentText, axis: .vertical)
                        .font(.system(size: 13))
                        .foregroundStyle(WebTheme.txt)
                        .tint(WebTheme.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(WebTheme.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(WebTheme.border, lineWidth: 1)
                        )
                        .focused($isFocused)
                        .lineLimit(1...3)
                    Button {
                        Task { await viewModel.submitComment() }
                    } label: {
                        if viewModel.isCommenting {
                            ProgressView()
                                .tint(.white)
                                .frame(width: 44, height: 36)
                        } else {
                            Text("发送")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 36)
                        }
                    }
                    .background(WebTheme.navGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Spacer()
            }
            .padding(16)
            .background(WebConsoleBackground())
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(WebTheme.blue)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }
}
