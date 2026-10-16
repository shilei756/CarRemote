import SwiftUI
import CarCore

/// 白名单管理面板（网页版 /admin/* 内嵌面板的 App 移植）
/// 流程与网页版一致：打开时按当天缓存密码自动登录 →
/// need_init 引导初始化（站主全局 / 管理员个人）→ 主面板
struct WhitelistView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // MARK: - 面板状态机（对应网页版 wlInitBox / wlSelfInitBox / wlLoginStep / wlPanelStep）

    private enum Step {
        case login        // 输入管理密码
        case initOwner    // 站主：初始化全局管理密码（/admin/whitelist/init）
        case initSelf     // 管理员：设置自己的管理密码（/admin/pass/init）
        case panel        // 主面板
    }

    // MARK: - 状态

    @State private var step: Step = .login
    @State private var passwordInput = ""
    @State private var initPass1 = ""
    @State private var initPass2 = ""
    @State private var adminPassword = ""          // 登录成功后的内存密码
    @State private var isWorking = false
    @State private var loginError: String?

    @State private var usage: AdminUsageData?
    @State private var isLoading = false
    @State private var banner: Banner?
    /// 使用者列表分页（网页版 WL_PAGE_SIZE = 10）
    private let pageSize = 10
    @State private var userPage = 1

    @State private var adminPhoneInput = ""
    @State private var wlPhoneInput = ""
    @State private var cardNote = ""
    @State private var cardCount = 1
    @State private var cardHasExpire = false
    @State private var cardExpire = Date()
    @State private var newCards: [String] = []
    @State private var cards: [AdminCard] = []
    @State private var isLoadingCards = false

    /// 确认弹窗（替代网页版 confirm）
    private struct PendingConfirm: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let action: () -> Void
    }
    @State private var pendingConfirm: PendingConfirm?

    private struct Banner: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    private var caller: String { appState.credentials?.phone ?? "" }

    // MARK: -  body

    var body: some View {
        NavigationStack {
            ZStack {
                WebConsoleBackground()
                content
            }
            .navigationTitle("白名单管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                        .foregroundStyle(WebTheme.blue)
                }
            }
        }
        .task { await bootstrap() }
        .alert(item: $pendingConfirm) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                primaryButton: .destructive(Text("确定")) { item.action() },
                secondaryButton: .cancel()
            )
        }
        .onChange(of: banner) { _, newValue in
            if newValue != nil {
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    banner = nil
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .login:
            loginStep
        case .initOwner:
            initStep(
                title: "设置管理密码",
                subtitle: "首次使用，请设置全局管理密码（至少 4 位）。之后管理员登录都使用该密码。",
                buttonTitle: "保存并进入",
                action: submitOwnerInit
            )
        case .initSelf:
            initStep(
                title: "设置你的管理密码",
                subtitle: "作为管理员，请设置你的管理密码（至少 4 位）。之后进入请使用该密码。",
                buttonTitle: "保存并进入",
                action: submitSelfInit
            )
        case .panel:
            panelBody
        }
    }

    // MARK: - 登录 / 初始化

    private var loginStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(title: "管理密码", sakura: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("输入管理密码后进入白名单管理面板。")
                            .font(.system(size: 12))
                            .foregroundStyle(WebTheme.muted)
                        SecureField("管理密码", text: $passwordInput)
                            .font(.system(size: 15))
                            .textContentType(.password)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(WebTheme.card2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1))
                        if let loginError {
                            Text(loginError)
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.red)
                        }
                        Button {
                            Task { await doLogin(passwordInput) }
                        } label: {
                            HStack {
                                Spacer()
                                if isWorking {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("进入管理面板")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WebTheme.blue)
                        .disabled(isWorking || passwordInput.isEmpty)
                    }
                }
                Spacer()
            }
            .padding(16)
        }
    }

    private func initStep(title: String, subtitle: String, buttonTitle: String, action: @escaping () -> Void) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionCard(title: title, sakura: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(WebTheme.muted)
                        SecureField("新密码（至少 4 位）", text: $initPass1)
                            .font(.system(size: 15))
                            .textContentType(.newPassword)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(WebTheme.card2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1))
                        SecureField("再次输入新密码", text: $initPass2)
                            .font(.system(size: 15))
                            .textContentType(.newPassword)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(WebTheme.card2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1))
                        if let loginError {
                            Text(loginError)
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.red)
                        }
                        Button(action: action) {
                            HStack {
                                Spacer()
                                if isWorking {
                                    ProgressView().tint(.white)
                                } else {
                                    Text(buttonTitle)
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                Spacer()
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WebTheme.blue)
                        .disabled(isWorking || initPass1.isEmpty || initPass2.isEmpty)
                    }
                }
                Spacer()
            }
            .padding(16)
        }
    }

    // MARK: - 主面板

    private var panelBody: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                if let banner {
                    HStack(spacing: 6) {
                        Image(systemName: banner.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        Text(banner.text)
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(banner.isError ? WebTheme.red : WebTheme.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .transition(.opacity)
                }
                summaryCard
                usersCard
                if let usage, !usage.blocked.isEmpty {
                    blockedCard
                }
                if let usage, usage.isOwner {
                    adminsCard
                    whitelistCard
                    cardsCard
                }
                logoutButton
            }
            .padding(16)
        }
        .overlay(alignment: .top) {
            if isLoading {
                ProgressView()
                    .tint(WebTheme.blue)
                    .padding(8)
                    .background(WebTheme.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: WebTheme.cardShadow, radius: 8, x: 0, y: 2)
                    .padding(.top, 8)
            }
        }
    }

    /// 汇总三卡（网页版 wlSummary）
    private var summaryCard: some View {
        HStack(spacing: 10) {
            summaryCell(value: usage?.people ?? 0, label: "使用人数", tint: WebTheme.purple)
            summaryCell(value: usage?.total ?? 0, label: "打开次数", tint: WebTheme.blue)
            summaryCell(value: usage?.blocked.count ?? 0, label: "已限制", tint: WebTheme.red)
        }
    }

    private func summaryCell(value: Int, label: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(WebTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tint.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// 使用者列表（网页版 wlList：每页 10 条 + 底部分页条）
    private var usersCard: some View {
        SectionCard(title: "使用者明细", sakura: false) {
            VStack(spacing: 8) {
                if let usage, !usage.items.isEmpty {
                    ForEach(pagedUsers) { item in
                        userRow(item)
                    }
                    pagerRow
                } else {
                    Text("暂无记录 · 有人打开网站后这里会显示")
                        .font(.system(size: 12))
                        .foregroundStyle(WebTheme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
        }
    }

    /// 当前页的使用者（对齐网页版 _renderUsersPage 的 slice 逻辑）
    private var pagedUsers: [AdminUsageItem] {
        guard let usage else { return [] }
        let totalPages = max(1, (usage.items.count + pageSize - 1) / pageSize)
        if userPage > totalPages { userPage = totalPages }
        if userPage < 1 { userPage = 1 }
        let start = (userPage - 1) * pageSize
        return Array(usage.items.dropFirst(start).prefix(pageSize))
    }

    /// 分页条（网页版 _pagerHTML：上一页 / 页码 / 下一页 + 共 N 个）
    private var pagerRow: some View {
        let total = usage?.items.count ?? 0
        let totalPages = max(1, (total + pageSize - 1) / pageSize)
        return VStack(spacing: 2) {
            HStack(spacing: 14) {
                Button {
                    userPage -= 1
                } label: {
                    Text("‹ 上一页")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(userPage <= 1 ? WebTheme.faint : WebTheme.blue)
                }
                .disabled(userPage <= 1)
                Text("\(userPage) / \(totalPages)")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(WebTheme.muted)
                Button {
                    userPage += 1
                } label: {
                    Text("下一页 ›")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(userPage >= totalPages ? WebTheme.faint : WebTheme.blue)
                }
                .disabled(userPage >= totalPages)
            }
            .padding(.top, 9)
            Text("共 \(total) 个 · 每页 \(pageSize) 个")
                .font(.system(size: 10))
                .foregroundStyle(WebTheme.faint)
        }
        .frame(maxWidth: .infinity)
    }

    private func userRow(_ item: AdminUsageItem) -> some View {
        let isBlocked = usage?.blocked.contains(item.phone) ?? false
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isBlocked ? WebTheme.red : (item.owner ? WebTheme.amber : WebTheme.purple))
                Text(item.phone)
                    .font(.system(size: 12.5))
                    .monospacedDigit()
                    .foregroundStyle(WebTheme.txt)
                badgeChip(item.badgeText)
                if isBlocked {
                    badgeChip("已限制", tint: WebTheme.red)
                }
                Spacer()
            }
            Text("首次 \(item.first) · 最近 \(item.last) · \(item.count) 次")
                .font(.system(size: 10))
                .foregroundStyle(WebTheme.faint)
            if !item.owner {
                HStack(spacing: 8) {
                    smallActionButton("强制下线", tint: WebTheme.red) {
                        askConfirm(
                            title: "强制下线 \(item.phone)",
                            message: "对方当前页面会被迫退出，凭证被清除，再次登录需要重新获得授权。"
                        ) {
                            Task { await runAction("已强制下线") { try await AdminService.forceLogout(caller: caller, target: item.phone) } }
                        }
                    }
                    if item.admin {
                        smallActionButton("卸任", tint: Color(hex: 0xea580c)) {
                            askConfirm(title: "卸任 \(item.phone)", message: "确定撤销该用户的管理员身份？") {
                                Task { await runAction("已卸任") { try await AdminService.removeAdmin(password: adminPassword, phone: item.phone, caller: caller) } }
                            }
                        }
                    }
                    smallActionButton("删除", tint: WebTheme.muted) {
                        askConfirm(title: "删除 \(item.phone)", message: "确定删除该使用记录？（仅清记录，不影响其登录使用）") {
                            Task { await runAction("已删除") { try await AdminService.deleteRecord(password: adminPassword, phone: item.phone, caller: caller) } }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func badgeChip(_ text: String, tint: Color? = nil) -> some View {
        let color = tint ?? badgeColor(text)
        return Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2.5)
            .background(color.opacity(0.12))
            .foregroundStyle(color)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func badgeColor(_ text: String) -> Color {
        switch text {
        case "站主": return WebTheme.amber
        case "管理员": return Color(hex: 0xea580c)
        case "白名单": return WebTheme.green
        case "体验": return WebTheme.blue
        default: return WebTheme.red
        }
    }

    /// 已限制列表（网页版 wlBlockedList）
    private var blockedCard: some View {
        SectionCard(title: "已限制", sakura: false) {
            VStack(spacing: 8) {
                ForEach(usage?.blocked ?? [], id: \.self) { phone in
                    let count = usage?.items.first(where: { $0.phone == phone })?.count ?? 0
                    HStack(spacing: 6) {
                        Image(systemName: "nosign")
                            .font(.system(size: 13))
                            .foregroundStyle(WebTheme.red)
                        Text(phone)
                            .font(.system(size: 12.5))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.txt)
                        Text("\(count) 次")
                            .font(.system(size: 10))
                            .foregroundStyle(WebTheme.muted)
                        Spacer()
                        smallActionButton("解除", tint: WebTheme.green) {
                            askConfirm(title: "解除限制", message: "确定解除对 \(phone) 的使用限制？") {
                                Task { await runAction("已解除限制") { try await AdminService.unblock(password: adminPassword, phone: phone, caller: caller) } }
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(WebTheme.card2)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    /// 管理员任命（网页版 wlOwnerBox 的任命部分）
    private var adminsCard: some View {
        SectionCard(title: "管理员任命", sakura: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text("管理员可查看统计和限制用户，但不能修改管理员名单和白名单。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(WebTheme.faint)
                HStack(spacing: 8) {
                    TextField("输入手机号", text: $adminPhoneInput)
                        .font(.system(size: 14))
                        .keyboardType(.phonePad)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(WebTheme.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1))
                    Button("任命") {
                        Task { await runAction("已任命 \(adminPhoneInput)") { try await AdminService.addAdmin(password: adminPassword, phone: adminPhoneInput, caller: caller) }; adminPhoneInput = "" }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WebTheme.blue)
                    .disabled(adminPhoneInput.isEmpty)
                }
                if let usage, !usage.admins.isEmpty {
                    VStack(spacing: 6) {
                        ForEach(usage.admins, id: \.self) { phone in
                            HStack {
                                Image(systemName: "person.badge.shield.checkmark")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Color(hex: 0xea580c))
                                Text(phone)
                                    .font(.system(size: 12.5))
                                    .monospacedDigit()
                                    .foregroundStyle(WebTheme.txt)
                                Spacer()
                                smallActionButton("卸任", tint: Color(hex: 0xea580c)) {
                                    askConfirm(title: "卸任 \(phone)", message: "确定撤销该用户的管理员身份？") {
                                        Task { await runAction("已卸任") { try await AdminService.removeAdmin(password: adminPassword, phone: phone, caller: caller) } }
                                    }
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(WebTheme.card2)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                } else {
                    Text("暂无管理员")
                        .font(.system(size: 11))
                        .foregroundStyle(WebTheme.faint)
                }
            }
        }
    }

    /// 白名单开关与名单（网页版 wlWlBox）
    private var whitelistCard: some View {
        SectionCard(title: "登录白名单", sakura: false) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    Task { await runAction(nil) { try await AdminService.toggleWhitelist(password: adminPassword, caller: caller, enable: !(usage?.wlEnabled ?? false)) } }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: usage?.wlEnabled == true ? "checkmark.square.fill" : "square")
                            .font(.system(size: 16))
                        Text(usage?.wlEnabled == true ? "已开启 · 点击关闭" : "已关闭 · 点击开启")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(usage?.wlEnabled == true ? WebTheme.green : WebTheme.muted)
                }
                .buttonStyle(.plain)

                if usage?.wlEnabled == true {
                    HStack(spacing: 8) {
                        TextField("添加白名单手机号", text: $wlPhoneInput)
                            .font(.system(size: 14))
                            .keyboardType(.phonePad)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(WebTheme.card2)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1))
                        Button("添加") {
                            Task { await runAction("已添加 \(wlPhoneInput)") { try await AdminService.addWhitelistPhone(password: adminPassword, phone: wlPhoneInput, caller: caller) }; wlPhoneInput = "" }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(WebTheme.green)
                        .disabled(wlPhoneInput.isEmpty)
                    }
                    if let usage, !usage.whitelist.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(usage.whitelist, id: \.self) { phone in
                                HStack {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(WebTheme.green)
                                    Text(phone)
                                        .font(.system(size: 12.5))
                                        .monospacedDigit()
                                        .foregroundStyle(WebTheme.txt)
                                    Text("已授权")
                                        .font(.system(size: 10))
                                        .foregroundStyle(WebTheme.muted)
                                    Spacer()
                                    smallActionButton("取消", tint: WebTheme.red) {
                                        askConfirm(title: "取消授权", message: "确定将 \(phone) 移出白名单？") {
                                            Task { await runAction("已取消授权") { try await AdminService.removeWhitelistPhone(password: adminPassword, phone: phone, caller: caller) } }
                                        }
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(WebTheme.card2)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                        }
                    } else {
                        Text("授权名单为空 · 开启后只有你和管理员能登录")
                            .font(.system(size: 11))
                            .foregroundStyle(WebTheme.faint)
                    }
                }
            }
        }
    }

    /// 体验卡密（网页版 cardBox）
    private var cardsCard: some View {
        SectionCard(title: "体验卡密", sakura: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text("生成卡密发给他人，对方登录后输入即可体验。每张卡密首次输入即开始计时，自激活起 24 小时内有效。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(WebTheme.faint)

                // 生成表单
                VStack(alignment: .leading, spacing: 10) {
                    TextField("备注（可选，如：朋友试用）", text: $cardNote)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(WebTheme.card2)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1))
                    HStack {
                        Text("数量")
                            .font(.system(size: 13))
                            .foregroundStyle(WebTheme.muted)
                        Stepper("", value: $cardCount, in: 1...10)
                            .labelsHidden()
                        Text("\(cardCount) 张")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.txt)
                    }
                    Toggle("设置到期日", isOn: $cardHasExpire)
                        .font(.system(size: 13))
                        .tint(WebTheme.blue)
                    if cardHasExpire {
                        DatePicker("到期日", selection: $cardExpire, displayedComponents: .date)
                            .font(.system(size: 13))
                            .tint(WebTheme.blue)
                    }
                    Button {
                        Task { await generateCards() }
                    } label: {
                        HStack {
                            Spacer()
                            Text("生成卡密")
                                .font(.system(size: 14, weight: .semibold))
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(WebTheme.blue)
                    .disabled(isWorking)
                }

                // 新生成结果
                if !newCards.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("本次生成 \(newCards.count) 张（点击复制）")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xbe185d))
                            Spacer()
                            Button("全部复制") {
                                UIPasteboard.general.string = newCards.joined(separator: "\n")
                                banner = Banner(text: "已复制全部卡密", isError: false)
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(WebTheme.blue)
                        }
                        FlowChips(items: newCards) { code in
                            UIPasteboard.general.string = code
                            banner = Banner(text: "卡密已复制：\(code)", isError: false)
                        }
                    }
                    .padding(10)
                    .background(Color(hex: 0xbe185d).opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // 卡密列表
                if isLoadingCards {
                    HStack {
                        Spacer()
                        ProgressView().tint(WebTheme.blue)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                } else if cards.isEmpty {
                    Text("暂无卡密")
                        .font(.system(size: 11))
                        .foregroundStyle(WebTheme.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(cards) { card in
                            cardRow(card)
                        }
                    }
                }
            }
        }
        .task { await loadCards() }
    }

    private func cardRow(_ card: AdminCard) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(card.code)
                    .font(.system(size: 12.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WebTheme.txt)
                Spacer()
                Text(card.stateText)
                    .font(.system(size: 9.5, weight: .semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(cardStateColor(card).opacity(0.12))
                    .foregroundStyle(cardStateColor(card))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            if !card.note.isEmpty {
                Text(card.note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WebTheme.muted)
            }
            HStack(spacing: 6) {
                if !card.usedBy.isEmpty {
                    Text("使用者 \(card.usedBy)")
                        .font(.system(size: 10))
                        .foregroundStyle(WebTheme.muted)
                    if card.remainMin > 0 {
                        Text("剩余 \(card.remainMin / 60) 小时 \(card.remainMin % 60) 分")
                            .font(.system(size: 10))
                            .foregroundStyle(WebTheme.muted)
                    }
                } else if !card.expireDate.isEmpty {
                    Text("到期 \(card.expireDate)")
                        .font(.system(size: 10))
                        .foregroundStyle(WebTheme.muted)
                }
                Spacer()
                Button(card.voided ? "恢复" : "作废") {
                    askConfirm(title: card.voided ? "恢复卡密" : "作废卡密", message: "确定\(card.voided ? "恢复" : "作废")卡密 \(card.code)？") {
                        Task { await runAction("已更新卡密状态") { try await AdminService.voidCard(password: adminPassword, code: card.code, void: !card.voided, caller: caller) } }
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(card.voided ? WebTheme.green : WebTheme.amber)
                Button("删除") {
                    askConfirm(title: "删除卡密", message: "确定彻底删除卡密 \(card.code)？删除后不可恢复。") {
                        Task { await runAction("已删除卡密") { try await AdminService.deleteCard(password: adminPassword, code: card.code, caller: caller) } }
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(WebTheme.red)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.card2)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func cardStateColor(_ card: AdminCard) -> Color {
        if card.voided { return WebTheme.muted }
        if !card.usedBy.isEmpty && card.remainMin <= 0 { return WebTheme.red }
        if !card.usedBy.isEmpty { return WebTheme.green }
        if card.available { return WebTheme.blue }
        return WebTheme.red
    }

    private var logoutButton: some View {
        Button {
            wlClearPassCache()
            adminPassword = ""
            usage = nil
            step = .login
            passwordInput = ""
        } label: {
            HStack {
                Spacer()
                Text("退出管理")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            .padding(.vertical, 11)
        }
        .buttonStyle(.bordered)
        .tint(WebTheme.red)
        .padding(.top, 4)
    }

    // MARK: - 逻辑

    /// 打开面板：与网页版 openWhitelistSheet 一致——先用当天缓存密码尝试，
    /// 无缓存则用空密码探测 need_init / not_admin 分支
    private func bootstrap() async {
        let cached = wlLoadPassCache()
        await doLogin(cached)
    }

    private func doLogin(_ password: String) async {
        guard !caller.isEmpty else {
            loginError = "请先登录账号"
            return
        }
        isWorking = true
        loginError = nil
        defer { isWorking = false }
        do {
            let data = try await AdminService.login(password: password, caller: caller)
            adminPassword = password
            if !password.isEmpty { wlSavePassCache(password) }
            usage = data
            step = .panel
            await loadCardsIfOwner()
        } catch let error as AdminService.AuthError {
            wlClearPassCache()
            adminPassword = ""
            switch error {
            case .needInit(let ownerInit):
                step = ownerInit ? .initOwner : .initSelf
            case .notAdmin:
                loginError = "仅管理员可查看"
                dismiss()
            case .wrongPassword:
                step = .login
                if !password.isEmpty { loginError = "管理密码错误" }
            case .server(let message):
                loginError = message
            }
        } catch {
            loginError = error.localizedDescription
        }
    }

    private func submitOwnerInit() {
        guard initPass1.count >= 4 else { loginError = "管理密码至少 4 位"; return }
        guard initPass1 == initPass2 else { loginError = "两次输入的密码不一致"; return }
        let newPass = initPass1
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try await AdminService.initWhitelist(password: newPass, caller: caller)
                initPass1 = ""
                initPass2 = ""
                await doLogin(newPass)
            } catch {
                loginError = error.localizedDescription
            }
        }
    }

    private func submitSelfInit() {
        guard initPass1.count >= 4 else { loginError = "管理密码至少 4 位"; return }
        guard initPass1 == initPass2 else { loginError = "两次输入的密码不一致"; return }
        Task {
            isWorking = true
            defer { isWorking = false }
            do {
                try await AdminService.initPassword(initPass1, caller: caller)
                let newPass = initPass1
                initPass1 = ""
                initPass2 = ""
                await doLogin(newPass)
                banner = Banner(text: "管理密码已设置", isError: false)
            } catch {
                loginError = error.localizedDescription
            }
        }
    }

    /// 刷新统计数据（网页版 wlRefresh）
    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let data = try await AdminService.login(password: adminPassword, caller: caller)
            usage = data
        } catch let error as AdminService.AuthError {
            wlClearPassCache()
            adminPassword = ""
            step = .login
            loginError = error.errorDescription
        } catch {
            banner = Banner(text: error.localizedDescription, isError: true)
        }
    }

    private func loadCardsIfOwner() async {
        guard usage?.isOwner == true else { return }
        await loadCards()
    }

    private func loadCards() async {
        isLoadingCards = true
        defer { isLoadingCards = false }
        do {
            cards = try await AdminService.listCards(password: adminPassword, caller: caller)
        } catch {
            cards = []
        }
    }

    private func generateCards() async {
        isWorking = true
        defer { isWorking = false }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expire = cardHasExpire ? formatter.string(from: cardExpire) : ""
        do {
            let codes = try await AdminService.generateCards(
                password: adminPassword, caller: caller,
                count: cardCount, note: cardNote, expireDate: expire
            )
            newCards = codes
            cardNote = ""
            banner = Banner(text: "已生成 \(codes.count) 张卡密", isError: false)
            await loadCards()
        } catch {
            banner = Banner(text: error.localizedDescription, isError: true)
        }
    }

    /// 通用操作：执行 → 成功提示 → 刷新面板
    private func runAction(_ successText: String?, _ operation: @escaping () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
            if let successText {
                banner = Banner(text: successText, isError: false)
            }
            await refresh()
            if usage?.isOwner == true {
                await loadCards()
            }
        } catch {
            banner = Banner(text: error.localizedDescription, isError: true)
        }
    }

    private func askConfirm(title: String, message: String, action: @escaping () -> Void) {
        pendingConfirm = PendingConfirm(title: title, message: message, action: action)
    }

    // MARK: - 管理密码当天缓存（与网页版一致的跨天失效策略）

    private func wlToday() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private func wlSavePassCache(_ password: String) {
        UserDefaults.standard.set(password, forKey: "wl_pass_cache")
        UserDefaults.standard.set(wlToday(), forKey: "wl_pass_day")
    }

    private func wlLoadPassCache() -> String {
        guard UserDefaults.standard.string(forKey: "wl_pass_day") == wlToday() else { return "" }
        return UserDefaults.standard.string(forKey: "wl_pass_cache") ?? ""
    }

    private func wlClearPassCache() {
        UserDefaults.standard.removeObject(forKey: "wl_pass_cache")
        UserDefaults.standard.removeObject(forKey: "wl_pass_day")
    }
}

// MARK: - 紧凑操作按钮（网页版 .wl-del 小按钮）

private struct AdminSmallButton: View {
    let title: String
    var tint: Color = WebTheme.blue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(tint.opacity(0.08))
                .foregroundStyle(tint)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

extension WhitelistView {
    fileprivate func smallActionButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        AdminSmallButton(title: title, tint: tint, action: action)
    }
}

// MARK: - 流式标签布局（新生成卡密 chips）

private struct FlowChips: View {
    let items: [String]
    let onTap: (String) -> Void

    var body: some View {
        // 简化：等宽换行网格
        let columns = [GridItem(.adaptive(minimum: 88), spacing: 6)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Button {
                    onTap(item)
                } label: {
                    Text(item)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(WebTheme.card)
                        .foregroundStyle(Color(hex: 0xbe185d))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Color(hex: 0xfbcfe8), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
