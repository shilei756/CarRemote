import SwiftUI
import Foundation
import CarCore

// MARK: - 在线版本自检（1.12.0）
//
// 目标：用户不必逐个分发安装包。站主出新包后，只需在 App 内「发布新版本」
// 页改一次 version.json（版本号 / 更新说明 / 下载页链接），所有用户打开 App
// 或切回前台时自动对比版本，发现新版即弹窗提示，点「立即更新」打开站主
// 配置的下载页（里面放重签安装方式 / 二维码 / 网盘链接）。
//
// 下发通道完全复用公告服务的成熟做法：GitHub 仓库 version.json + jsDelivr CDN
// （国内稳定）+ GitHub API / raw 兜底，令牌只存本机钥匙串，绝不写进 App 包。
// 注意：这是「提醒 + 引导」而非静默覆盖安装 —— iOS 沙盒不允许 App 自己装 IPA，
// 用户仍需点一次安装，但省掉了站主逐个私聊分发的麻烦。

// MARK: 数据模型

struct AppRelease: Codable, Equatable {
    /// 语义版本号，如 "1.12.0"
    var version: String
    /// 构建号（可选，仅展示）
    var build: String
    /// 更新说明（多行）
    var notes: String
    /// 下载页 URL（站主放安装包 / 安装指引的网页）
    var updateURL: String
    /// 是否强制更新（强制时弹窗不可「稍后再说」）
    var force: Bool
    /// false = 客户端忽略这次更新（用于紧急撤回）
    var enabled: Bool

    init(version: String = "", build: String = "", notes: String = "",
         updateURL: String = "", force: Bool = false, enabled: Bool = false) {
        self.version = version
        self.build = build
        self.notes = notes
        self.updateURL = updateURL
        self.force = force
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case version, build, notes, updateURL, force, enabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        build = try c.decodeIfPresent(String.self, forKey: .build) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        updateURL = try c.decodeIfPresent(String.self, forKey: .updateURL) ?? ""
        force = try c.decodeIfPresent(Bool.self, forKey: .force) ?? false
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(build, forKey: .build)
        try c.encode(notes, forKey: .notes)
        try c.encode(updateURL, forKey: .updateURL)
        try c.encode(force, forKey: .force)
        try c.encode(enabled, forKey: .enabled)
    }
}

enum UpdateError: LocalizedError {
    case unavailable(Int)
    case http(Int, String)
    var errorDescription: String? {
        switch self {
        case .unavailable(let code): return "暂时读取不到版本信息（HTTP \(code)）"
        case .http(let code, let msg): return "GitHub 返回 HTTP \(code)：\(msg)"
        }
    }
}

// MARK: 版本比较（语义化，忽略前导 v，补齐段数）

enum VersionCompare {
    /// a > b 返回 .orderedDescending
    static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let ai = parts(a), bi = parts(b)
        let n = max(ai.count, bi.count)
        for i in 0..<n {
            let av = i < ai.count ? ai[i] : 0
            let bv = i < bi.count ? bi[i] : 0
            if av > bv { return .orderedDescending }
            if av < bv { return .orderedAscending }
        }
        return .orderedSame
    }

    private static func parts(_ v: String) -> [Int] {
        let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "", options: .caseInsensitive)
        return trimmed.split(separator: ".").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? 0 }
    }
}

// MARK: 服务层

enum UpdateService {
    private static let owner = "shilei756"
    private static let repo = "CarRemote"
    private static let branch = "main"
    private static let path = "version.json"
    private static let tokenKey = "announcement.github.token"   // 复用公告令牌，不重复索取

    static var githubToken: String? {
        get { KeychainStore.get(tokenKey) }
        set {
            if let value = newValue, !value.isEmpty {
                KeychainStore.set(value, forKey: tokenKey)
            } else {
                KeychainStore.remove(tokenKey)
            }
        }
    }
    static var hasToken: Bool { githubToken?.isEmpty == false }

    private static var contentsAPI: String {
        "https://api.github.com/repos/\(owner)/\(repo)/contents/\(path)"
    }
    private static var cdnURL: String {
        "https://cdn.jsdelivr.net/gh/\(owner)/\(repo)@\(branch)/\(path)"
    }
    private static var rawURL: String {
        "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(path)"
    }
    private static var purgeURL: String {
        "https://purge.jsdelivr.net/gh/\(owner)/\(repo)@\(branch)/\(path)"
    }

    /// 本地当前版本
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    static var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    /// 拉取线上版本信息：CDN → GitHub API → raw 多源回退，取 version 最高的一条。
    static func fetchLatest(preferRealtime: Bool = false) async throws -> AppRelease {
        let ts = Int(Date().timeIntervalSince1970)
        let api = "\(contentsAPI)?ref=\(branch)&t=\(ts)"
        let cdn = "\(cdnURL)?t=\(ts)"
        let raw = "\(rawURL)?t=\(ts)"
        let ordered = preferRealtime ? [api, cdn, raw] : [cdn, api, raw]

        var candidates: [AppRelease] = []
        var lastCode = -1
        for (index, urlString) in ordered.enumerated() {
            if index >= 2, !candidates.isEmpty { break }
            guard let url = URL(string: urlString) else { continue }
            var request = URLRequest(url: url,
                                     cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                     timeoutInterval: 8)
            if urlString == api {
                request.setValue("application/vnd.github.raw", forHTTPHeaderField: "Accept")
                request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
                if let token = githubToken, !token.isEmpty {
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                }
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                lastCode = code
                guard code == 200, !data.isEmpty else { continue }
                if let release = try? JSONDecoder().decode(AppRelease.self, from: data),
                   !release.version.isEmpty {
                    candidates.append(release)
                }
            } catch { continue }
        }
        if let newest = candidates.max(by: { VersionCompare.compare($0.version, $1.version) == .orderedAscending }) {
            return newest
        }
        throw UpdateError.unavailable(lastCode)
    }

    /// 站主发布：PUT GitHub Contents API 后清 CDN 缓存。
    static func publish(_ release: AppRelease, token: String) async throws {
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw UpdateError.http(-1, "缺少令牌") }

        var sha: String?
        if let url = URL(string: "\(contentsAPI)?ref=\(branch)&t=\(Int(Date().timeIntervalSince1970))") {
            var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 12)
            applyAuth(&req, token: t)
            if let (data, resp) = try? await URLSession.shared.data(for: req),
               (resp as? HTTPURLResponse)?.statusCode == 200,
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let s = obj["sha"] as? String { sha = s }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let fileData = try encoder.encode(release)
        var payload: [String: Any] = [
            "message": "chore(version): 发布版本 \(release.version)",
            "content": fileData.base64EncodedString(),
            "branch": branch
        ]
        if let sha { payload["sha"] = sha }

        guard let putURL = URL(string: contentsAPI) else { throw UpdateError.unavailable(-1) }
        var putReq = URLRequest(url: putURL, timeoutInterval: 20)
        putReq.httpMethod = "PUT"
        putReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&putReq, token: t)
        putReq.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (respData, resp) = try await URLSession.shared.data(for: putReq)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
        guard (200...299).contains(code) else {
            let msg = (try? JSONSerialization.jsonObject(with: respData) as? [String: Any])?["message"] as? String
                ?? "请确认令牌具备该仓库写入权限"
            throw UpdateError.http(code, msg)
        }
        if let purge = URL(string: purgeURL) {
            var purgeReq = URLRequest(url: purge, timeoutInterval: 8)
            _ = try? await URLSession.shared.data(for: purgeReq)
        }
    }

    private static func applyAuth(_ request: inout URLRequest, token: String) {
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
    }
}

// MARK: 更新中心（全局状态）

@MainActor
final class UpdateCenter: ObservableObject {
    @Published var pending: AppRelease?
    @Published var latest: AppRelease?
    @Published var isBusy = false

    private let checkKey = "update.lastCheckAt"
    /// 用户点「稍后再说」后记住该版本，同一版本当天不再弹（第二天可再提醒）
    private let skippedKey = "update.skippedVersion"
    private let skippedDateKey = "update.skippedDate"

    private var skippedVersion: String? {
        get { UserDefaults.standard.string(forKey: skippedKey) }
        set { UserDefaults.standard.set(newValue, forKey: skippedKey) }
    }

    /// 进入主界面 / 回前台检查。30 分钟内不重复请求。
    func check(force: Bool = false) async {
        if !force,
           let last = UserDefaults.standard.object(forKey: checkKey) as? Date,
           Date().timeIntervalSince(last) < 30 * 60 { return }
        UserDefaults.standard.set(Date(), forKey: checkKey)
        guard let release = try? await UpdateService.fetchLatest() else { return }
        latest = release
        guard release.enabled else { pending = nil; return }
        // 线上版本 > 本地版本才提示
        guard VersionCompare.compare(release.version, UpdateService.currentVersion) == .orderedDescending else {
            pending = nil
            return
        }
        // 强制更新忽略「稍后」；否则同一版本当天已跳过则不再弹
        if !release.force, skippedVersion == release.version,
           let d = UserDefaults.standard.object(forKey: skippedDateKey) as? Date,
           Calendar.current.isDateInToday(d) {
            pending = nil
            return
        }
        pending = release
    }

    func refreshLatest() async {
        isBusy = true
        defer { isBusy = false }
        if let release = try? await UpdateService.fetchLatest(preferRealtime: true) {
            latest = release
        }
    }

    func skip(_ version: String) {
        skippedVersion = version
        UserDefaults.standard.set(Date(), forKey: skippedDateKey)
        pending = nil
    }

    func dismiss() { pending = nil }
}

// MARK: - 更新弹窗

struct AppUpdateSheet: View {
    let release: AppRelease
    let onLater: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    private var hasLink: Bool {
        let s = release.updateURL.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.hasPrefix("http://") || s.hasPrefix("https://")
    }

    var body: some View {
        ZStack {
            WebTheme.bg0.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    if !release.force {
                        Button {
                            onLater()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(WebTheme.muted)
                        }
                        .accessibilityLabel("稍后再说")
                    }
                }
                .padding(.top, 12)
                .padding(.horizontal, 20)

                Spacer(minLength: 8)

                VStack(spacing: 16) {
                    ZStack {
                        Circle().fill(WebTheme.blue.opacity(0.16)).frame(width: 68, height: 68)
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(WebTheme.blue)
                    }

                    VStack(spacing: 4) {
                        Text("发现新版本")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(WebTheme.blue)
                        Text("v\(release.version)")
                            .font(.system(size: 26, weight: .heavy))
                            .foregroundStyle(WebTheme.txt)
                        if !release.build.isEmpty {
                            Text("构建 \(release.build)")
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.faint)
                        }
                    }

                    if !release.notes.isEmpty {
                        ScrollView {
                            Text(release.notes)
                                .font(.system(size: 13))
                                .foregroundStyle(WebTheme.muted)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 220)
                        .padding(12)
                        .background(WebTheme.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }

                    if release.force {
                        Text("此版本需更新后才能继续使用")
                            .font(.system(size: 11))
                            .foregroundStyle(WebTheme.amber)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity)
                .background(WebTheme.card)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(WebTheme.border, lineWidth: 1)
                )
                .padding(.horizontal, 20)

                Spacer(minLength: 8)

                VStack(spacing: 10) {
                    if hasLink, let url = URL(string: release.updateURL) {
                        Button {
                            openURL(url)
                            if !release.force { onLater() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "safari")
                                Text("立即更新")
                            }
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(WebTheme.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("立即更新，打开下载页")
                    } else {
                        Text("下载链接由站主配置，请联系站主获取新版本")
                            .font(.system(size: 12))
                            .foregroundStyle(WebTheme.faint)
                            .multilineTextAlignment(.center)
                    }

                    if !release.force {
                        Button {
                            onLater()
                            dismiss()
                        } label: {
                            Text("稍后再说")
                                .font(.system(size: 13))
                                .foregroundStyle(WebTheme.muted)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("稍后再说")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
    }
}

// MARK: - 站主专属发布页（仅站主可见；复用公告令牌）

struct OwnerReleasePage: View {
    @EnvironmentObject private var center: UpdateCenter

    @State private var tokenDraft: String = UpdateService.githubToken ?? ""
    @State private var tokenSaved: Bool = UpdateService.hasToken
    @State private var version: String = ""
    @State private var build: String = ""
    @State private var notes: String = ""
    @State private var updateURL: String = ""
    @State private var force = false
    @State private var enabled = true
    @State private var isPublishing = false
    @State private var statusText = ""
    @State private var statusOK = true

    var body: some View {
        Form {
            Section {
                if let cur = center.latest {
                    infoRow("线上版本", "v\(cur.version)", tint: cur.enabled ? WebTheme.green : WebTheme.muted)
                    infoRow("状态", cur.enabled ? "已发布" : "已撤回", tint: cur.enabled ? WebTheme.green : WebTheme.faint)
                    infoRow("本机版本", "v\(UpdateService.currentVersion) (b\(UpdateService.currentBuild))", tint: WebTheme.txt)
                    if !cur.updateURL.isEmpty {
                        infoRow("下载页", cur.updateURL, tint: WebTheme.blue)
                    }
                } else {
                    HStack {
                        Text("线上版本").font(.system(size: 13)).foregroundStyle(WebTheme.txt)
                        Spacer()
                        if center.isBusy { ProgressView() }
                        Text("读取中…").font(.system(size: 12)).foregroundStyle(WebTheme.faint)
                    }
                }
                Button { Task { await center.refreshLatest() } } label: {
                    Text("刷新线上版本").font(.system(size: 13))
                }
                .disabled(center.isBusy)
            } header: {
                Text("线上版本")
            }

            Section {
                SecureField("粘贴访问令牌（与公告同一枚）", text: $tokenDraft)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .font(.system(size: 12).monospaced())
                HStack(spacing: 12) {
                    Button {
                        let t = tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        UpdateService.githubToken = t.isEmpty ? nil : t
                        tokenSaved = !t.isEmpty
                        statusText = t.isEmpty ? "已清除本机令牌。" : "已保存到本机钥匙串。"
                        statusOK = true
                    } label: {
                        Text("保存到本机").font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(WebTheme.blue).foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    Button {
                        UpdateService.githubToken = nil
                        tokenDraft = ""
                        tokenSaved = false
                        statusText = "已清除本机令牌。"
                    } label: {
                        Text("清除").font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .background(WebTheme.card).foregroundStyle(WebTheme.txt)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
                HStack(spacing: 6) {
                    Image(systemName: tokenSaved ? "checkmark.shield.fill" : "shield.slash")
                        .font(.system(size: 12))
                        .foregroundStyle(tokenSaved ? WebTheme.green : WebTheme.amber)
                    Text(tokenSaved ? "本机已保存令牌，可直接发布" : "尚未保存令牌，发布前需先保存")
                        .font(.system(size: 11)).foregroundStyle(WebTheme.faint)
                }
            } header: {
                Text("发布凭据")
            } footer: {
                Text("与「发布公告」共用同一枚 GitHub 令牌，只需保存一次。令牌只存本机钥匙串，不写入 App 包。")
            }

            Section {
                TextField("版本号，如 1.12.0", text: $version)
                    .font(.system(size: 14))
                    .textInputAutocapitalization(.never)
                TextField("构建号（可选），如 96", text: $build)
                    .font(.system(size: 14))
                ZStack(alignment: .topLeading) {
                    if notes.isEmpty {
                        Text("本次更新说明（支持换行，用户弹窗里显示）")
                            .font(.system(size: 14)).foregroundStyle(WebTheme.faint)
                            .padding(.top, 8).padding(.leading, 4)
                    }
                    TextEditor(text: $notes)
                        .font(.system(size: 14)).frame(minHeight: 100)
                }
                TextField("下载页链接 https://…（放安装包/安装指引）", text: $updateURL)
                    .font(.system(size: 12))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                Toggle("强制更新（用户不能点稍后）", isOn: $force)
                    .font(.system(size: 13))
                Toggle("立即生效（关闭=撤回更新提示）", isOn: $enabled)
                    .font(.system(size: 13))
            } header: {
                Text("版本信息")
            } footer: {
                Text("只有线上版本号高于用户本机版本才会弹窗。同版本号不会重复打扰。")
            }

            Section {
                Button {
                    Task { await publish(enabled: enabled) }
                } label: {
                    HStack(spacing: 8) {
                        if isPublishing { ProgressView() }
                        Text(enabled ? "发布新版本" : "撤回更新提示")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                    .background(enabled ? WebTheme.blue : WebTheme.card)
                    .foregroundStyle(enabled ? .white : WebTheme.red)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isPublishing)
                Button {
                    // 一键带入本机当前版本，避免手填出错
                    version = UpdateService.currentVersion
                    build = UpdateService.currentBuild
                } label: {
                    Text("填入本机版本号").font(.system(size: 13))
                }
            }

            if !statusText.isEmpty {
                Section {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: statusOK ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(statusOK ? WebTheme.green : WebTheme.amber)
                        Text(statusText).font(.system(size: 12)).foregroundStyle(WebTheme.muted)
                    }
                }
            }
        }
        .hideScrollBackground()
        .inlineTitle("发布新版本")
        .task {
            await center.refreshLatest()
            if let cur = center.latest {
                version = cur.version
                build = cur.build
                notes = cur.notes
                updateURL = cur.updateURL
                force = cur.force
                enabled = cur.enabled
            } else {
                version = UpdateService.currentVersion
                build = UpdateService.currentBuild
            }
        }
    }

    private func infoRow(_ label: String, _ value: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label).font(.system(size: 12)).foregroundStyle(WebTheme.faint)
                .frame(width: 64, alignment: .leading)
            Text(value).font(.system(size: 12)).foregroundStyle(tint)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func publish(enabled publishEnabled: Bool) async {
        guard let token = UpdateService.githubToken, !token.isEmpty else {
            statusText = "请先在上方保存具备仓库写入权限的令牌。"
            statusOK = false
            return
        }
        let v = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if publishEnabled, v.isEmpty {
            statusText = "请填写版本号。"
            statusOK = false
            return
        }
        isPublishing = true
        defer { isPublishing = false }
        let release = AppRelease(version: v, build: build.trimmingCharacters(in: .whitespacesAndNewlines),
                                 notes: notes, updateURL: updateURL.trimmingCharacters(in: .whitespacesAndNewlines),
                                 force: force, enabled: publishEnabled)
        do {
            try await UpdateService.publish(release, token: token)
            statusText = publishEnabled
                ? "已发布 v\(v)。用户下次打开 App 或回前台即可看到更新提示（CDN 约 1–2 分钟生效）。"
                : "已撤回，用户端不再提示更新。"
            statusOK = true
            await center.refreshLatest()
        } catch {
            statusText = "发布失败：\(error.localizedDescription)"
            statusOK = false
        }
    }
}
