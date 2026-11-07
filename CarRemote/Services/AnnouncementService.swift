import Foundation
import SwiftUI
import CarCore

// MARK: - 站主后台公告（App 侧读取）
//
// 后台网站 admin/server.js 提供公开 GET /api/notice，返回最新公告 JSON。
// App 每次启动拉取一次，仅当「公告 id 与上次已读不同」时弹窗，避免重复打扰。
// 后台未部署 / 接口不存在 / 网络异常时全部静默跳过，绝不干扰登录与控车主流程。

struct SiteAnnouncement: Identifiable, Codable {
    var id: String
    var title: String
    var body: String
    var date: String?
    /// info / warning，仅用于标题图标配色
    var level: String?
}

@MainActor
final class AnnouncementCenter: ObservableObject {
    @Published var current: SiteAnnouncement?

    func check() async {
        let base = APIConfig.adminSiteBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/api/notice") else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let notice = try JSONDecoder().decode(SiteAnnouncement.self, from: data)
            guard !notice.id.isEmpty, !notice.title.isEmpty else { return }
            guard notice.id != SharedStore.loadAnnouncementLastID() else { return }
            current = notice
        } catch {
            // 静默：后台未部署不影响 App 使用
        }
    }

    func dismiss(_ notice: SiteAnnouncement) {
        SharedStore.saveAnnouncementLastID(notice.id)
        current = nil
    }
}

/// 公告弹层：Modal 必须提供明确关闭按钮（Apple HIG）
struct AnnouncementSheet: View {
    let notice: SiteAnnouncement
    let onDismiss: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var isWarning: Bool { notice.level == "warning" }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(WebTheme.border)
                .frame(width: 36, height: 4)
                .padding(.top, 10)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill((isWarning ? WebTheme.amber : WebTheme.blue).opacity(0.14))
                        .frame(width: 38, height: 38)
                    Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "megaphone.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isWarning ? WebTheme.amber : WebTheme.blue)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("系统公告")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WebTheme.muted)
                    if let date = notice.date, !date.isEmpty {
                        Text(date)
                            .font(.system(size: 11))
                            .foregroundStyle(WebTheme.faint)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)

            Text(notice.title)
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(WebTheme.txt)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 16)

            ScrollView {
                Text(notice.body)
                    .font(.system(size: 14))
                    .lineSpacing(5)
                    .foregroundStyle(WebTheme.txt)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
            }
            .frame(maxHeight: 260)

            Button {
                onDismiss()
                dismiss()
            } label: {
                Text("知道了")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(WebTheme.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
            .accessibilityLabel("关闭公告")
        }
        .background(WebTheme.card)
        // 不使用 presentationDetents（iOS 16+ 专属，部署目标 15.0 会编译报错），
        // 由 sheet 按内容自适应高度，兼容 iOS 15。
    }
}

// MARK: - 设置页：查看公告

struct NoticePage: View {
    @State private var notice: SiteAnnouncement?
    @State private var loading = true
    @State private var hint = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在获取公告…")
                            .font(.system(size: 13))
                            .foregroundStyle(WebTheme.muted)
                    }
                    .padding(.top, 24)
                } else if let n = notice {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: n.level == "warning"
                                  ? "exclamationmark.triangle.fill" : "megaphone.fill")
                                .foregroundStyle(n.level == "warning" ? WebTheme.amber : WebTheme.blue)
                            Text(n.date ?? "最新公告")
                                .font(.system(size: 12))
                                .foregroundStyle(WebTheme.muted)
                        }
                        Text(n.title)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(WebTheme.txt)
                        Text(n.body)
                            .font(.system(size: 14))
                            .lineSpacing(5)
                            .foregroundStyle(WebTheme.txt)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WebTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "tray")
                            .font(.system(size: 34))
                            .foregroundStyle(WebTheme.faint)
                        Text("暂无公告")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(WebTheme.txt)
                        Text(hint)
                            .font(.system(size: 12))
                            .foregroundStyle(WebTheme.muted)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                }
            }
            .padding(16)
        }
        .background {
            WebConsoleBackground()
                .ignoresSafeArea()
        }
        .navigationTitle("系统公告")
        .refreshable { await load() }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        let base = APIConfig.adminSiteBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/api/notice") else {
            hint = "后台地址无效，请到「我的 → 网站后台」修改"
            notice = nil
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                hint = "后台无响应"; notice = nil; return
            }
            guard http.statusCode == 200 else {
                hint = "后台未连接（HTTP \(http.statusCode)）。部署 admin/server.js 后即可发布公告。"
                notice = nil
                return
            }
            notice = try JSONDecoder().decode(SiteAnnouncement.self, from: data)
        } catch {
            hint = "未能连接网站后台，请检查「我的 → 网站后台」里的地址"
            notice = nil
        }
    }
}

// MARK: - 设置页（仅站主）：网站后台地址

struct AdminSitePage: View {
    @State private var draft: String = APIConfig.adminSiteBaseURL
    @State private var savedTip = false
    @State private var testResult = ""

    var body: some View {
        Form {
            Section {
                Text("网站后台是随仓库一起交付的独立服务 admin/server.js（Node 零依赖）。登录后可以发布公告、封禁/解封用户、管理白名单与卡密、查看使用统计。")
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.muted)
                Text("在网页后台限制某人后，App 回前台复查授权时同样会被拦截；在 App 里封禁的人，网页后台也查得到——两边共用同一套 /admin 权限接口。")
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.muted)
            } header: {
                Text("关于后台")
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前后台地址")
                        .font(.system(size: 12, weight: .semibold))
                    Text(APIConfig.adminSiteBaseURL)
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(WebTheme.faint)
                        .textSelection(.enabled)
                }
                TextField("后台地址，如 https://admin.example.com", text: $draft)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack(spacing: 12) {
                    Button {
                        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        SharedStore.saveAdminSiteBaseURL(trimmed.isEmpty ? nil : trimmed)
                        draft = trimmed.isEmpty ? APIConfig.defaultSiteBaseURL : trimmed
                        withAnimation { savedTip = true }
                    } label: {
                        Text("保存")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(WebTheme.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    Button {
                        SharedStore.saveAdminSiteBaseURL(nil)
                        draft = APIConfig.defaultSiteBaseURL
                        withAnimation { savedTip = true }
                    } label: {
                        Text("恢复默认")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(WebTheme.card2)
                            .foregroundStyle(WebTheme.txt)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
                if savedTip {
                    Text("已保存，重启 App 或下拉「系统公告」即可生效")
                        .font(.system(size: 11))
                        .foregroundStyle(WebTheme.green)
                }
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("测试公告接口")
                            .font(.system(size: 13))
                        Spacer()
                        if !testResult.isEmpty {
                            Text(testResult)
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.muted)
                        }
                    }
                }
                .buttonStyle(.plain)
            } header: {
                Text("连接设置")
            } footer: {
                Text("默认密码 admin888，启动服务时用环境变量 ADMIN_PASSWORD 修改。服务可以跑在你自己的电脑、NAS 或任意云主机上。")
            }
        }
        .navigationTitle("网站后台")
    }

    @MainActor
    private func testConnection() async {
        testResult = "测试中…"
        let base = APIConfig.adminSiteBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: base + "/api/notice") else {
            testResult = "地址无效"; return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            testResult = code == 200 ? "连接正常" : "HTTP \(code)"
        } catch {
            testResult = "无法连接"
        }
    }
}
