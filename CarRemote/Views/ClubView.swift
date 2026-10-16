import SwiftUI
import PhotosUI
import UIKit
import CarCore

/// 圈子（玩车社区）
struct ClubView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: ClubViewModel

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: ClubViewModel(appState: appState))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let errorMessage = viewModel.errorMessage {
                        infoBanner(errorMessage, color: .red)
                    }
                    if viewModel.isLoading && viewModel.posts.isEmpty {
                        ProgressView("加载中…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    } else if viewModel.posts.isEmpty {
                        EmptyStateView(
                            systemImage: "bubble.left.and.bubble.right",
                            title: "还没有动态",
                            message: "点击右上角发布第一条用车心得吧"
                        )
                    } else {
                        LazyVStack(spacing: 16) {
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
                    Spacer(minLength: 24)
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("玩车圈子")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.publishContent = ""
                        viewModel.pickedImages = []
                        viewModel.publishError = nil
                        viewModel.showPublish = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("发布动态")
                }
            }
            .refreshable {
                await viewModel.load()
            }
            .task {
                await viewModel.load()
            }
            .sheet(isPresented: $viewModel.showPublish) {
                PublishSheet(viewModel: viewModel)
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
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// 单条动态卡片
struct PostCard: View {
    let post: ClubPost
    let isLiked: Bool
    let onLike: () -> Void
    let onComment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 头部
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 40, height: 40)
                    if !post.avatar.isEmpty, let url = URL(string: post.avatar) {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Image(systemName: "person.fill")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.nick)
                        .font(.subheadline.bold())
                    HStack(spacing: 6) {
                        Text(post.typeName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        if !post.timeText.isEmpty {
                            Text(post.timeText)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }

            // 正文
            Text(post.content)
                .font(.subheadline)
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
                                    .fill(Color(.tertiarySystemBackground))
                                    .overlay(ProgressView())
                            }
                            .frame(height: 220)
                            .clipped()
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            // 操作栏
            HStack(spacing: 24) {
                Button(action: onLike) {
                    HStack(spacing: 4) {
                        Image(systemName: isLiked ? "heart.fill" : "heart")
                            .foregroundStyle(isLiked ? .pink : .secondary)
                        Text("\(post.likeCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isLiked ? "取消点赞" : "点赞")

                Button(action: onComment) {
                    HStack(spacing: 4) {
                        Image(systemName: "bubble.right")
                            .foregroundStyle(.secondary)
                        Text("\(post.commentCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("评论")

                Spacer()
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

/// 发布动态
struct PublishSheet: View {
    @ObservedObject var viewModel: ClubViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker("类型", selection: $viewModel.publishType) {
                        ForEach(ClubPostType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    ZStack(alignment: .topLeading) {
                        if viewModel.publishContent.isEmpty {
                            Text("分享你的用车心得、反馈问题或提出建议…")
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 12)
                        }
                        TextEditor(text: $viewModel.publishContent)
                            .frame(minHeight: 120)
                            .padding(4)
                    }
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    // 已选图片
                    if !viewModel.pickedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(viewModel.pickedImages.enumerated()), id: \.offset) { index, image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 72, height: 72)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(alignment: .topTrailing) {
                                            Button {
                                                viewModel.pickedImages.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .foregroundStyle(.white, .black.opacity(0.6))
                                            }
                                            .offset(x: 4, y: -4)
                                        }
                                }
                            }
                        }
                    }

                    PhotosPicker(
                        selection: $selectedItems,
                        maxSelectionCount: 9,
                        matching: .images
                    ) {
                        Label("添加图片（最多 9 张）", systemImage: "photo.badge.plus")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(12)
                            .background(Color(.tertiarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }

                    if let publishError = viewModel.publishError {
                        Text(publishError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await viewModel.publish() }
                    } label: {
                        if viewModel.isPublishing {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(14)
                        } else {
                            Text("发布")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(14)
                        }
                    }
                    .disabled(!viewModel.canPublish)
                    .buttonStyle(.plain)

                    Spacer(minLength: 24)
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle("发布动态")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("取消") { dismiss() }
                }
            }
            .interactiveDismissDisabled(viewModel.isPublishing)
            .onChange(of: selectedItems) { _, newItems in
                loadImages(from: newItems)
            }
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

/// 评论
struct CommentSheet: View {
    @ObservedObject var viewModel: ClubViewModel
    let post: ClubPost
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollView {
                    Text(post.content)
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 12) {
                    TextField("写评论…", text: $viewModel.commentText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($isFocused)
                        .lineLimit(1...3)
                    Button {
                        Task { await viewModel.submitComment() }
                    } label: {
                        if viewModel.isCommenting {
                            ProgressView()
                                .padding(8)
                        } else {
                            Text("发送")
                                .font(.headline)
                                .padding(8)
                        }
                    }
                    .disabled(viewModel.commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle("评论")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium])
    }
}
