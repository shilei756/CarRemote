import SwiftUI
import Foundation
import CarCore

// MARK: - 站主公告（1.6.0）
//
// 设计约束（对齐站主要求）：
// - 不恢复独立的网站后台，App 内不出现任何后台网址 / 后台入口给普通用户；
// - 「发布公告」入口只有站主账号可见（SettingsView 里用 ownerPhone 判定）；
// - 普通用户只在进入主界面后看到一次公告弹窗，看不到任何入口；
// - 公告数据放在 GitHub 仓库根目录 notice.json，读取走 jsDelivr CDN（国内实测可达），
//   GitHub API / raw 作为兜底；发布走 GitHub Contents API，令牌只存本机钥匙串，
//   绝不写进源码或随 IPA 分发。
//
// 为什么用 GitHub 仓库文件而不是独立后台：站主此前给的网站后台地址打不开，
// 且明确要求「后台不需要在软件里体现」。GitHub 仓库是现成、免运维、国内可读的
// 下发通道；发布后主动 purge jsDelivr 缓存，保证「随时发、随时能看到」。

// MARK: 数据模型

/// 一条公告。字段全部给默认值，避免服务端 JSON 缺字段导致解析失败、弹窗逻辑异常。
struct SiteAnnouncement: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var body: String
    var date: String
    /// info / warn / urgent，决定弹窗强调色
    var level: String
    /// false = 已下线，客户端不弹窗
    var enabled: Bool

    init(id: String, title: String, body: String, date: String, level: String, enabled: Bool) {
        self.id = id
        self.title = title
        self.body = body
        self.date = date
        self.level = level
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, body, date, level, enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 缺失 id 时给固定值而不是随机值：随机值会让「已读去重」失效、反复弹窗
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "notice-unknown"
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date) ?? ""
        level = try c.decodeIfPresent(String.self, forKey: .level) ?? "info"
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(date, forKey: .date)
        try c.encode(level, forKey: .level)
        try c.encode(enabled, forKey: .enabled)
    }

    var hasContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum AnnouncementError: LocalizedError {
    case missingToken
    case unavailable(Int)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingToken:
            return "缺少具备仓库写入权限的访问令牌"
        case .unavailable(let code):
            return "暂时读取不到公告（HTTP \(code)），请稍后重试"
        case .http(let code, let message):
            return "GitHub 返回 HTTP \(code)：\(message)"
        }
    }
}

// MARK: - 配置与网络层

enum AnnouncementService {

    // 仓库与文件路径（集中管理；UI 层不展示这些地址）
    private static let owner = "shilei756"
    private static let repo = "CarRemote"
    private static let branch = "main"
    private static let path = "notice.json"

    private static let githubTokenKey = "announcement.github.token"

    /// 站主 GitHub 访问令牌：只存本机钥匙串，App 包内不含任何令牌。
    static var githubToken: String? {
        get { KeychainStore.get(githubTokenKey) }
        set {
            if let value = newValue, !value.isEmpty {
                KeychainStore.set(value, forKey: githubTokenKey)
            } else {
                KeychainStore.remove(githubTokenKey)
            }
        }
    }

    static var hasToken: Bool { githubToken?.isEmpty == false }

    static func nowString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: Date())
    }

    private static var contentsAPI: String {
        "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)"
    }

    private static var cdnURL: String {
        "https://cdn.jsdelivr.net/gh/\(owner)/\(repo)@\(branch)/\(path)"
    }

    private static var purgeURL: String {
        "https://purge.jsdelivr.net/gh/\(owner)/\(repo)@\(branch)/\(path)"
    }

    private static var rawURL: String {
        "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(path)"
    }

    /// 拉取线上公告。多源串行回退：
    /// - 常规读取优先 jsDelivr（国内稳定、无限流），发布时已 purge，内容是最新的；
    /// - 发布页刷新用 preferRealtime，优先 GitHub API contents（raw，实时无 CDN 缓存）；
    /// - raw.githubusercontent 作为境外 / 部分网络下的实时兜底；
    /// - 三个源全部读一遍，取发布时间最新的一条（见下方实现说明）。
    /// 1.7.0 关键修正：**不能「第一个源成功就返回」**。
    /// 实测 jsDelivr 对 `@main` 分支有缓存，站主发布后 purge 也需要约 1–2 分钟
    /// 才能全网生效；这段时间 CDN 仍会返回上一条公告（甚至是 enabled=false
    /// 的占位文件），若直接返回就会把刚发布的公告整个漏掉。
    /// 改为把可用源都读一遍，按「发布时间 + id」取最新的一条：
    /// CDN 快但可能有延迟，GitHub API / raw 实时兜底，两者互相校正。
    static func fetchLatest(preferRealtime: Bool = false) async throws -> SiteAnnouncement {
        let ts = Int(Date().timeIntervalSince1970)
        let api = "\(contentsAPI)?ref=\(branch)&t=\(ts)"
        let cdn = cdnURL
        let raw = "\(rawURL)?t=\(ts)"
        let ordered = preferRealtime ? [api, cdn, raw] : [cdn, api, raw]

        var candidates: [SiteAnnouncement] = []
        var lastCode = -1
        for (index, urlString) in ordered.enumerated() {
            // 前两个源（CDN + API）已有结果就不必再打第三个 raw：
            // 部分网络下 raw 不可达，白等一个超时没有意义。
            if index >= 2, !candidates.isEmpty { break }
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url,
                                     cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                     timeoutInterval: 8)
            if urlString == api {
                // 直接取文件原始内容，避免再解析 base64；带 t 参数规避中间缓存
                request.setValue("application/vnd.github.raw", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                // 站主设备已保存令牌时用认证请求，避开匿名 60 次/小时限流
                if let token = githubToken, !token.isEmpty {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                lastCode = code
                guard code == 200, !data.isEmpty else { continue }
                // API 被限流 / 文件不存在时会返回 JSON 错误体，decode 失败即跳过
                if let notice = try? JSONDecoder().decode(SiteAnnouncement.self, from: data) {
                    candidates.append(notice)
                }
            } catch {
                continue
            }
        }

        // date 格式为 "yyyy-MM-dd HH:mm"，字符串序即时间序；
        // 占位公告 date 为空串，永远排在真实公告之前，不会被误选。
        if let newest = candidates.max(by: { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.id < rhs.id
        }) {
            return newest
        }
        throw AnnouncementError.unavailable(lastCode)
    }

    /// 站主发布 / 下线公告：PUT GitHub Contents API，成功后主动清 jsDelivr 缓存。
    static func publish(_ notice: SiteAnnouncement, token: String) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AnnouncementError.missingToken }

        // 1) 取当前文件 sha（更新已有文件必须带，新建则不带）
        var sha: String?
        if let url = URL(string: "\(contentsAPI)?ref=\(branch)&t=\(Int(Date().timeIntervalSince1970))") {
            var getRequest = URLRequest(url: url,
                                        cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                        timeoutInterval: 12)
            applyAuth(&getRequest, token: trimmed)
            if let (data, response) = try? await URLSession.shared.data(for: getRequest),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let value = object["sha"] as? String {
                sha = value
            }
        }

        // 2) PUT 新内容
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let fileData = try encoder.encode(notice)
        var payload: [String: Any] = [
            "message": "chore(notice): 站主\(notice.enabled ? "发布" : "下线")公告 \(notice.id)",
            "content": fileData.base64EncodedString(),
            "branch": branch
        ]
        if let sha { payload["sha"] = sha }

        guard let putURL = URL(string: contentsAPI) else { throw AnnouncementError.unavailable(-1) }
        var putRequest = URLRequest(url: putURL, timeoutInterval: 20)
        putRequest.httpMethod = "PUT"
        putRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&putRequest, token: trimmed)
        putRequest.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (respData, response) = try await URLSession.shared.data(for: putRequest)
        let code = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else {
            let message = (try? JSONSerialization.jsonObject(with: respData) as? [String: Any])?["message"] as? String
                ?? "请确认令牌具备该仓库的写入权限"
            throw AnnouncementError.http(code, message)
        }

        // 3) 清 CDN 缓存，保证普通用户能立刻读到新公告（失败不影响发布结果）
        if let purge = URL(string: purgeURL) {
            var purgeRequest = URLRequest(url: purge, timeoutInterval: 8)
            _ = try? await URLSession.shared.data(for: purgeRequest)
        }
    }

    private static func applyAuth(_ request: inout URLRequest, token: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    }
}

// MARK: - 公告中心（全局状态）

@MainActor
final class AnnouncementCenter: ObservableObject {
    @Published var pending: SiteAnnouncement?
    @Published var latest: SiteAnnouncement?
    @Published var isBusy = false

    private let readKey = "announcement.lastReadId"
    private let checkKey = "announcement.lastCheckAt"

    private var lastReadId: String? {
        get { UserDefaults.standard.string(forKey: readKey) }
        set { UserDefaults.standard.set(newValue, forKey: readKey) }
    }

    /// 进入主界面 / 回前台时检查。20 秒内不重复请求，避免频繁切后台打爆 GitHub API 限流。
    func check(force: Bool = false) async {
        if !force,
           let last = UserDefaults.standard.object(forKey: checkKey) as? Date,
           Date().timeIntervalSince(last) < 20 { return }
        UserDefaults.standard.set(Date(), forKey: checkKey)
        do {
            apply(try await AnnouncementService.fetchLatest())
        } catch {
            // 网络异常完全静默：公告是增强功能，绝不能打扰正常使用
        }
    }

    /// 站主发布页用：强制走实时源刷新当前线上公告。
    func refreshLatest() async {
        isBusy = true
        defer { isBusy = false }
        if let notice = try? await AnnouncementService.fetchLatest(preferRealtime: true) {
            latest = notice
        }
    }

    private func apply(_ notice: SiteAnnouncement) {
        latest = notice
        guard notice.enabled, notice.hasContent else {
            pending = nil
            return
        }
        // 同一条公告只弹一次：用户点过「我知道了」或下拉关闭后不再重复
        guard notice.id != lastReadId else {
            pending = nil
            return
        }
        guard pending?.id != notice.id else { return }
        pending = notice
    }

    func markRead(_ id: String) {
        lastReadId = id
        if pending?.id == id { pending = nil }
    }
}

// MARK: - 公告弹窗（所有用户可见，无入口）

struct AnnouncementSheet: View {
    let notice: SiteAnnouncement
    let onRead: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var accent: Color {
        switch notice.level {
        case "urgent": return WebTheme.red
        case "warn": return WebTheme.amber
        default: return WebTheme.blue
        }
    }

    private var symbol: String {
        switch notice.level {
        case "urgent": return "exclamationmark.triangle.fill"
        case "warn": return "bell.badge.fill"
        default: return "megaphone.fill"
        }
    }

    private var levelText: String {
        switch notice.level {
        case "urgent": return "紧急"
        case "warn": return "重要"
        default: return "公告"
        }
    }

    var body: some View {
        ZStack {
            WebTheme.bg0.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button {
                        onRead()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(WebTheme.muted)
                    }
                    .accessibilityLabel("关闭公告")
                }
                .padding(.top, 12)

                Spacer(minLength: 12)

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(accent.opacity(0.16))
                            .frame(width: 68, height: 68)
                        Image(systemName: symbol)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(accent)
                    }

                    Text(levelText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.14))
                        .clipShape(Capsule())

                    Text(notice.title.isEmpty ? "站主公告" : notice.title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(WebTheme.txt)
                        .multilineTextAlignment(.center)

                    if !notice.date.isEmpty {
                        Text(notice.date)
                            .font(.system(size: 11))
                            .foregroundStyle(WebTheme.faint)
                    }

                    if !notice.body.isEmpty {
                        ScrollView {
                            Text(notice.body)
                                .font(.system(size: 14))
                                .foregroundStyle(WebTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 240)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .background(WebTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(WebTheme.border, lineWidth: 1)
                )

                Spacer(minLength: 12)

                Button {
                    onRead()
                    dismiss()
                } label: {
                    Text("我知道了")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("我知道了，关闭公告")
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
        // 下拉关闭也记为已读，避免下次回前台反复弹出
        .onDisappear { onRead() }
    }
}

// MARK: - 站主专属发布页（仅 ownerPhone 可见）

struct OwnerAnnouncementPage: View {
    @EnvironmentObject private var center: AnnouncementCenter

    @State private var tokenDraft: String = AnnouncementService.githubToken ?? ""
    @State private var tokenSaved: Bool = AnnouncementService.hasToken
    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var level: String = "info"
    @State private var isPublishing = false
    @State private var statusText = ""
    @State private var statusOK = true

    var body: some View {
        Form {
            Section {
                if let current = center.latest {
                    infoRow("当前状态", current.enabled ? "已上线" : "已下线",
                            tint: current.enabled ? WebTheme.green : WebTheme.muted)
                    if current.enabled, !current.title.isEmpty {
                        infoRow("标题", current.title, tint: WebTheme.txt)
                    }
                    if !current.date.isEmpty {
                        infoRow("发布时间", current.date, tint: WebTheme.muted)
                    }
                    infoRow("公告 ID", current.id, tint: WebTheme.faint)
                } else {
                    HStack {
                        Text("当前公告")
                            .font(.system(size: 13))
                            .foregroundStyle(WebTheme.txt)
                        Spacer()
                        if center.isBusy { ProgressView() }
                        Text("读取中…")
                            .font(.system(size: 12))
                            .foregroundStyle(WebTheme.faint)
                    }
                }
                Button {
                    Task { await center.refreshLatest() }
                } label: {
                    Text("刷新线上公告")
                        .font(.system(size: 13))
                }
                .disabled(center.isBusy)
            } header: {
                Text("线上公告")
            }

            Section {
                SecureField("粘贴访问令牌", text: $tokenDraft)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(size: 12).monospaced())
                HStack(spacing: 12) {
                    Button {
                        let t = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        AnnouncementService.githubToken = t.isEmpty ? nil : t
                        tokenSaved = !t.isEmpty
                        statusText = t.isEmpty ? "已清除本机令牌。" : "已保存到本机钥匙串，不会随 App 分发。"
                        statusOK = true
                    } label: {
                        Text("保存到本机")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(WebTheme.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    Button {
                        AnnouncementService.githubToken = nil
                        tokenDraft = ""
                        tokenSaved = false
                        statusText = "已清除本机令牌。"
                        statusOK = true
                    } label: {
                        Text("清除")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(WebTheme.card)
                            .foregroundStyle(WebTheme.txt)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 6) {
                    Image(systemName: tokenSaved ? "checkmark.shield.fill" : "shield.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(tokenSaved ? WebTheme.green : WebTheme.amber)
                    Text(tokenSaved ? "本机已保存令牌，可直接发布" : "尚未保存令牌，发布前需先保存")
                        .font(.system(size: 11))
                        .foregroundStyle(WebTheme.faint)
                }
            } header: {
                Text("发布凭据")
            } footer: {
                Text("需要一枚具备本仓库写入权限的 GitHub 访问令牌。令牌仅保存在本机钥匙串，不写入 App 安装包，也不会上传。此页面与发布能力仅站主账号可见，普通用户只能收到公告弹窗。")
            }

            Section {
                TextField("公告标题", text: $title)
                    .font(.system(size: 14))
                ZStack(alignment: .topLeading) {
                    if bodyText.isEmpty {
                        Text("公告正文（支持换行）")
                            .font(.system(size: 14))
                            .foregroundStyle(WebTheme.faint)
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    TextEditor(text: $bodyText)
                        .font(.system(size: 14))
                        .frame(minHeight: 110)
                }
                Picker("公告类型", selection: $level) {
                    Text("普通").tag("info")
                    Text("重要").tag("warn")
                    Text("紧急").tag("urgent")
                }
                .pickerStyle(SegmentedPickerStyle())
            } header: {
                Text("编辑内容")
            } footer: {
                Text("每次发布会生成新的公告 ID，用户端会重新弹出一次；已点过「我知道了」的旧公告不会重复打扰。")
            }

            Section {
                Button {
                    Task { await publish(enabled: true) }
                } label: {
                    HStack(spacing: 8) {
                        if isPublishing { ProgressView() }
                        Text("发布公告")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(WebTheme.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isPublishing)

                Button {
                    Task { await publish(enabled: false) }
                } label: {
                    Text("下线当前公告")
                        .font(.system(size: 14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(WebTheme.card)
                        .foregroundStyle(WebTheme.red)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isPublishing)
            }

            if !statusText.isEmpty {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: statusOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(statusOK ? WebTheme.green : WebTheme.amber)
                        Text(statusText)
                            .font(.system(size: 12))
                            .foregroundStyle(WebTheme.muted)
                    }
                }
            }
        }
        .hideScrollBackground()
        .inlineTitle("发布公告")
        .task {
            await center.refreshLatest()
            if let current = center.latest, current.enabled {
                title = current.title
                bodyText = current.body
                level = current.level
            }
        }
    }

    private func infoRow(_ label: String, _ value: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.faint)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(tint)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func publish(enabled: Bool) async {
        guard let token = AnnouncementService.githubToken, !token.isEmpty else {
            statusText = "请先在上方保存具备仓库写入权限的访问令牌。"
            statusOK = false
            return
        }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if enabled, t.isEmpty && b.isEmpty {
            statusText = "请填写公告标题或正文。"
            statusOK = false
            return
        }

        isPublishing = true
        defer { isPublishing = false }

        let id: String
        if enabled {
            id = "notice-\(Int(Date().timeIntervalSince1970))"
        } else {
            id = center.latest?.id ?? "notice-off-\(Int(Date().timeIntervalSince1970))"
        }
        let notice = SiteAnnouncement(id: id, title: t, body: b,
                                      date: AnnouncementService.nowString(),
                                      level: level, enabled: enabled)
        do {
            try await AnnouncementService.publish(notice, token: token)
            statusText = enabled
                ? "已发布。用户下次打开 App 或回到前台即可看到（CDN 约 1–2 分钟全网生效，App 已做多源取最新，不会漏读）。"
                : "已下线，用户端不再弹出公告。"
            statusOK = true
            await center.refreshLatest()
        } catch {
            statusText = "发布失败：\(error.localizedDescription)"
            statusOK = false
        }
    }
}
