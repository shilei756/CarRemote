import SwiftUI
import CarCore
import UIKit

/// 我的（网页版 my 页样式：个人卡 + 切换车型横滑卡 + 设置列表行逐项进入子页 + 开发者信息 + 退出登录）
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var settings: AppSettings = SharedStore.loadSettings()
    @State private var showLogoutConfirm = false
    @State private var appTheme: AppTheme = SharedStore.loadAppTheme()
    // 服务器地址（仅站主可见）
    @State private var serverDraft: String = APIConfig.siteBaseURL
    @State private var serverSavedTip = false
    // 新版空调：剩余天数
    @State private var acRemainingDays: Int?
    @State private var showACQR = false

    var body: some View {
        NavStack {
            ZStack {
                WebConsoleBackground()
                ScrollView {
                    VStack(spacing: 14) {
                        profileCard
                        carModelCard
                        settingsListCard
                        developerCard
                        logoutButton
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
            .alert("退出登录", isPresented: $showLogoutConfirm) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) {
                    appState.logout()
                }
            } message: {
                Text("退出后需要重新输入手机号与控车码登录，本地记录不会丢失。")
            }
            .sheet(isPresented: $showACQR) {
                ACQRScanSheet {
                    Task { await loadACRemaining() }
                }
                .environmentObject(appState)
            }
            .task {
                // 兜底：确保管理员身份已探测（决定入口显隐）
                if !appState.isAdminUser {
                    await appState.refreshAdminRole()
                }
                await loadACRemaining()
            }
        }
        .tint(WebTheme.blue)
    }

    // MARK: - 个人卡片

    private var profileCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(WebTheme.blue.opacity(0.75))
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.credentials?.maskedPhone ?? "--")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
                Text("长安账号已绑定")
                    .font(.system(size: 11.5))
                    .foregroundStyle(WebTheme.muted)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(WebTheme.green).frame(width: 6, height: 6)
                Text("在线")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WebTheme.green)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(WebTheme.green.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(WebTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1))
    }

    // MARK: - 切换车型（横滑卡片）

    private var carModelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("切换车型")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
                Spacer()
                Text("左右滑动查看全部车型")
                    .font(.system(size: 10.5))
                    .foregroundStyle(WebTheme.faint)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(CarModelStyle.allCases, id: \.self) { style in
                        Button {
                            guard settings.carModelStyle != style else { return }
                            // 油箱容积联动车型默认值（网页版 CAR_MODELS.tank）
                            settings.carModelStyle = style
                            settings.tankCapacityL = style.tankCapacityL
                            saveSettings()
                        } label: {
                            VStack(spacing: 6) {
                                Image(style.sideImageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(height: 42)
                                Text(style.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(WebTheme.txt)
                                    .lineLimit(1)
                                Text("\(Int(style.tankCapacityL))L 油箱")
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(WebTheme.faint)
                            }
                            .frame(width: 112)
                            .padding(.vertical, 12)
                            .background(settings.carModelStyle == style ? WebTheme.blue.opacity(0.09) : WebTheme.card2.opacity(0.7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(settings.carModelStyle == style ? WebTheme.blue : WebTheme.border, lineWidth: settings.carModelStyle == style ? 1.5 : 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("切换车型为\(style.displayName)")
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WebTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1))
    }

    // MARK: - 设置列表（逐行进入子页）

    private var settingsListCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 3D 车模开关（逸动PLUS 2022 官方车模；行内切换，不用进子页）
            actionRow(symbol: "cube.fill", tint: WebTheme.blue,
                      title: "3D 车模", subtitle: "控车页显示可旋转的三维车模，关闭后显示平面车图",
                      trailing: {
                Text(settings.car3DEnabled ? "已开启" : "已关闭")
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.muted)
            }) {
                settings.car3DEnabled.toggle()
                saveSettings()
            }
            rowDivider
            // 免责声明
            linkRow(symbol: "exclamationmark.shield.fill", tint: WebTheme.amber,
                    title: "免责声明", subtitle: "使用前请务必阅读") {
                DisclaimerPage()
            }
            rowDivider
            // 夜间模式（行内切换，不进入子页）
            actionRow(symbol: "moon.fill", tint: Color.indigo,
                      title: "夜间模式", subtitle: "夜间自动切换深色界面",
                      trailing: {
                Text(appTheme == .dark ? "已开启" : "已关闭")
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.muted)
            }) {
                let next: AppTheme = appTheme == .dark ? .light : .dark
                appTheme = next
                ThemeManager.shared.set(next)
            }
            rowDivider
            // 背景壁纸
            linkRow(symbol: "photo.fill", tint: Color.pink,
                    title: "背景壁纸", subtitle: "樱花花瓣 / 神兽主题换装") {
                WallpaperSheet(isPushed: true)
                    .environmentObject(appState)
            }
            rowDivider
            // 新版空调开通
            linkRow(symbol: "wind", tint: WebTheme.blue,
                    title: "新版空调开通", subtitle: "扫码授权后可用新版空调控制") {
                acSettingsPage
            }
            rowDivider
            // 按钮设置
            linkRow(symbol: "slider.horizontal.3", tint: WebTheme.green,
                    title: "按钮设置", subtitle: "自定义控车页按钮布局与归属区") {
                LayoutEditorSheet(isPushed: true, viewModel: DashboardViewModel(appState: appState))
            }
            rowDivider
            // 防误触确认
            linkRow(symbol: "hand.raised.fill", tint: Color.orange,
                    title: "防误触确认", subtitle: "开锁等操作前需二次确认，按需开启") {
                ConfirmSettingsPage(settings: $settings)
            }
            rowDivider
            // 小组件控制按钮
            linkRow(symbol: "square.grid.2x2.fill", tint: WebTheme.purple,
                    title: "小组件控制按钮", subtitle: "自定义桌面组件上的控车按钮") {
                WidgetButtonsPage(settings: $settings)
            }
            rowDivider
            // Siri 语音控制
            linkRow(symbol: "waveform", tint: WebTheme.blue,
                    title: "Siri 语音控制", subtitle: "对 Siri 说短语即可控车",
                    trailing: {
                Text(settings.siriMasterEnabled ? "已开启" : "已关闭")
                    .font(.system(size: 12))
                    .foregroundStyle(WebTheme.muted)
            }) {
                SiriSettingsPage(settings: $settings)
            }
            rowDivider
            // 圈子资料
            linkRow(symbol: "person.text.rectangle", tint: Color.teal,
                    title: "圈子资料", subtitle: "发布动态时展示的昵称与头像") {
                ClubProfilePage(settings: $settings)
            }
            rowDivider
            // 白名单管理（网页版 applyAdminEntry：非管理员不显示）
            if appState.isAdminUser {
                linkRow(symbol: "shield.lefthalf.filled", tint: WebTheme.green,
                        title: "白名单管理", subtitle: "使用统计 · 限制用户 · 名单与卡密") {
                    WhitelistView(isPushed: true)
                        .environmentObject(appState)
                }
                rowDivider
            }
            // 服务器地址（仅站主）
            if appState.credentials?.phone == APIConfig.ownerPhone {
                linkRow(symbol: "server.rack", tint: WebTheme.muted,
                        title: "服务器地址", subtitle: "切换后端域名，无需重新出包") {
                    serverSettingsPage
                }
                rowDivider
            }
            // 关于
            linkRow(symbol: "info.circle.fill", tint: WebTheme.blue,
                    title: "关于", subtitle: "版本 · 网页版 · 联系站主") {
                AboutPage()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
        .background(WebTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1))
    }

    /// 行间分隔线
    private var rowDivider: some View {
        Rectangle()
            .fill(WebTheme.border.opacity(0.5))
            .frame(height: 0.5)
    }

    /// 进入子页的行（图标 + 标题 + 副标题 + 右侧箭头）
    private func linkRow<Destination: View, Trailing: View>(
        symbol: String, tint: Color, title: String, subtitle: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 12) {
                rowIcon(symbol: symbol, tint: tint)
                rowTexts(title: title, subtitle: subtitle)
                Spacer()
                trailing()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 行内动作的行（点击执行闭包，不进入子页）
    private func actionRow<Trailing: View>(
        symbol: String, tint: Color, title: String, subtitle: String,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                rowIcon(symbol: symbol, tint: tint)
                rowTexts(title: title, subtitle: subtitle)
                Spacer()
                trailing()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func rowIcon(symbol: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.12))
                .frame(width: 34, height: 34)
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private func rowTexts(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(WebTheme.txt)
            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(WebTheme.faint)
                .lineLimit(1)
        }
    }

    // MARK: - 新版空调子页

    private var acSettingsPage: some View {
        Form {
            Section {
                Picker("空调控制链路", selection: acModeBinding) {
                    Text("新版（扫码开通）").tag(ACMode.new)
                    Text("官方版（直连）").tag(ACMode.official)
                }
                .pickerStyle(.inline)
            } footer: {
                Text("新版走长安开放平台（开/关空调支持指定温度，与 App 内弹窗一致）；官方版为直连链路，按车机当前设定执行。")
            }
            Section {
                HStack {
                    Text("新版授权剩余")
                    Spacer()
                    if let days = acRemainingDays {
                        Text("\(days) 天")
                            .foregroundStyle(days <= 3 ? WebTheme.red : WebTheme.green)
                            .font(.system(size: 15, weight: .semibold))
                    } else {
                        Text("查询中…").foregroundStyle(.secondary)
                    }
                }
                Button {
                    showACQR = true
                } label: {
                    Label("扫码开通 / 续期新版空调", systemImage: "qrcode")
                        .foregroundStyle(WebTheme.blue)
                }
            } footer: {
                Text("用长安汽车 App 扫码授权开放平台后即可使用新版空调控制，授权到期前可再次扫码续期。")
            }
        }
        .hideScrollBackground()
        .inlineTitle("新版空调")
    }

    private var acModeBinding: Binding<ACMode> {
        Binding(
            get: { SharedStore.loadACMode() },
            set: { SharedStore.saveACMode($0) }
        )
    }

    private func loadACRemaining() async {
        guard let credentials = appState.credentials else { return }
        acRemainingDays = await ACService.activationRemainingDays(credentials: credentials)
    }

    // MARK: - 服务器地址子页（仅站主）

    private var serverSettingsPage: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前地址")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WebTheme.txt)
                    Text(APIConfig.siteBaseURL)
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(WebTheme.faint)
                        .textSelection(.enabled)
                }
                TextField("新域名，如 new.example.com", text: $serverDraft)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack(spacing: 12) {
                    Button {
                        let trimmed = serverDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        SharedStore.saveServerBaseURL(trimmed.isEmpty ? nil : trimmed)
                        serverDraft = trimmed
                        withAnimation { serverSavedTip = true }
                    } label: {
                        Text("保存并切换")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(WebTheme.blue)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    Button {
                        SharedStore.saveServerBaseURL(nil)
                        serverDraft = APIConfig.defaultSiteBaseURL
                        withAnimation { serverSavedTip = true }
                    } label: {
                        Text("恢复默认")
                            .font(.system(size: 13, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(WebTheme.card)
                            .foregroundStyle(WebTheme.txt)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                }
                if serverSavedTip {
                    Text("已保存，下次请求立即生效（建议重启 App 一次）。若新域名不通，改回默认地址即可恢复。")
                        .font(.system(size: 10))
                        .foregroundStyle(WebTheme.green)
                }
            } footer: {
                Text("只有站主账号（\(APIConfig.ownerPhone)）能看到此项。换域名/迁移后端时在此填入新地址即可，无需重新出包。注意：新域名必须仍指向同一套数据库，否则登录态、卡密、白名单都会失效。")
            }
        }
        .hideScrollBackground()
        .inlineTitle("服务器地址")
    }

    // MARK: - 开发者信息 + 退出登录

    private var developerCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("网页开发者")
                    .font(.system(size: 13))
                    .foregroundStyle(WebTheme.muted)
                Spacer()
                Text("世磊")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
            }
            .padding(.vertical, 12)
            Rectangle().fill(WebTheme.border.opacity(0.5)).frame(height: 0.5)
            HStack {
                Text("美化版作者")
                    .font(.system(size: 13))
                    .foregroundStyle(WebTheme.muted)
                Spacer()
                Text("世磊")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 14)
        .background(WebTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1))
    }

    private var logoutButton: some View {
        Button {
            showLogoutConfirm = true
        } label: {
            Text("退出登录")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(WebTheme.blue)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 工具

    private func saveSettings() {
        SharedStore.saveSettings(settings)
    }
}

// MARK: - 免责声明

struct DisclaimerPage: View {
    var body: some View {
        ZStack {
            WebConsoleBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    disclaimerCard(title: "一、应用性质", "「长安控车」为第三方爱好者开发的车辆辅助管理工具，并非长安汽车官方应用，与长安汽车及其关联公司无任何隶属或合作关系。长安汽车及相关商标的权利归其权利人所有。")
                    disclaimerCard(title: "二、数据与指令链路", "登录、车况查询与控车指令均通过长安官方渠道链路下发，本应用不存储您的长安账号密码；卡密授权、白名单与统计功能由站主自有后端提供。请妥善保管手机号与控车码，勿泄露给他人。")
                    disclaimerCard(title: "三、风险提示", "远程控车（开锁、闭锁、点火、熄火、开空调等）依赖车辆网络与服务端可用性，可能存在延迟或失败。请在执行指令前确认车辆周边环境安全；因网络异常、设备故障或误操作导致的任何损失，由使用者自行承担。")
                    disclaimerCard(title: "四、使用限制", "本应用仅供个人学习交流使用，禁止用于任何商业用途或非法用途。站主有权对违规账号限制使用或移出白名单，无需事先通知。")
                    disclaimerCard(title: "五、其他", "登录或继续使用即代表您已阅读并同意以上条款。条款如有更新，以最新版本 App 内展示为准。如有疑问请联系站主。")
                }
                .padding(16)
            }
        }
        .hideScrollBackground()
        .inlineTitle("免责声明")
    }

    private func disclaimerCard(title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14.5, weight: .bold))
                .foregroundStyle(WebTheme.txt)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(WebTheme.muted)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(WebTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1))
    }
}

// MARK: - 防误触确认子页

struct ConfirmSettingsPage: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(CarCommand.allCases, id: \.self) { command in
                    Toggle(isOn: confirmBinding(for: command)) {
                        Label(command.displayName, systemImage: command.sfSymbol)
                    }
                }
            } footer: {
                Text("开启后，执行开锁 / 闭锁 / 点火 / 熄火等指令前会弹窗确认。")
            }
        }
        .hideScrollBackground()
        .inlineTitle("防误触确认")
    }

    private func confirmBinding(for command: CarCommand) -> Binding<Bool> {
        Binding(
            get: { settings.needsConfirm(command: command) },
            set: { _ in
                settings.toggleConfirm(command: command)
                saveSettings()
            }
        )
    }

    private func saveSettings() {
        SharedStore.saveSettings(settings)
    }
}

// MARK: - 小组件控制按钮子页

struct WidgetButtonsPage: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Section {
                ForEach(0..<5, id: \.self) { index in
                    Picker("按钮 \(index + 1)", selection: widgetCommandBinding(index)) {
                        ForEach(CarCommand.allCases, id: \.self) { command in
                            Text(command.displayName).tag(command.rawValue)
                        }
                    }
                }
            } footer: {
                Text("桌面小组件底部的 5 个控车按钮，点一下直接执行（不打开 App）。改完回到桌面等几秒自动刷新。")
            }
        }
        .hideScrollBackground()
        .inlineTitle("小组件控制按钮")
    }

    private func widgetCommandBinding(_ index: Int) -> Binding<String> {
        Binding<String>(
            get: {
                let commands = settings.widgetCommands
                return commands.indices.contains(index) ? commands[index] : CarModelStyle.defaultWidgetCommands[index]
            },
            set: { newValue in
                var commands = settings.widgetCommands
                while commands.count < 5 { commands.append("") }
                commands[index] = newValue
                settings.widgetCommands = commands
                saveSettings()
            }
        )
    }

    private func saveSettings() {
        SharedStore.saveSettings(settings)
    }
}

// MARK: - Siri 语音控制子页

struct SiriSettingsPage: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: siriMasterBinding) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("总开关")
                            Text("关闭后所有语音与快捷指令立即失效")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "waveform")
                    }
                }
            }
            Section {
                siriPhraseRow("解锁车辆", phrase: "用长安控车解锁车辆")
                siriPhraseRow("锁定车辆", phrase: "用长安控车锁上车")
                siriPhraseRow("查看车况", phrase: "长安控车车况怎么样")
                siriPhraseRow("寻车", phrase: "用长安控车找车")
                siriPhraseRow("空调", phrase: "用长安控车打开 / 关闭空调")
                siriPhraseRow("任意指令", phrase: "用长安控车控制车辆")
            } header: {
                Text("常用直达短语")
            } footer: {
                Text("对 Siri 说下表短语即可控车。点火、熄火等高危操作会先向你确认；「控制车辆」可触发任意指令，Siri 会追问要做什么。指令执行后会播报成功或失败。")
            }
        }
        .hideScrollBackground()
        .inlineTitle("Siri 语音控制")
    }

    private func siriPhraseRow(_ name: String, phrase: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .font(.system(size: 13, weight: .medium))
            Text("“\(phrase)”")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var siriMasterBinding: Binding<Bool> {
        Binding(
            get: { settings.siriMasterEnabled },
            set: { newValue in
                settings.siriMasterEnabled = newValue
                saveSettings()
            }
        )
    }

    private func saveSettings() {
        SharedStore.saveSettings(settings)
    }
}

// MARK: - 圈子资料子页

struct ClubProfilePage: View {
    @Binding var settings: AppSettings

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("昵称")
                    Spacer()
                    TextField("车友昵称", text: $settings.clubNick)
                        .multilineTextAlignment(.trailing)
                }
                HStack {
                    Text("头像")
                    Spacer()
                    TextField("图片链接或 Emoji", text: $settings.clubAvatar)
                        .multilineTextAlignment(.trailing)
                }
            } footer: {
                Text("发布动态时展示的昵称与头像，留空则显示脱敏手机号。修改后自动保存。")
            }
        }
        .hideScrollBackground()
        .inlineTitle("圈子资料")
        .compatOnChange(of: settings.clubNick) { _ in saveSettings() }
        .compatOnChange(of: settings.clubAvatar) { _ in saveSettings() }
    }

    private func saveSettings() {
        SharedStore.saveSettings(settings)
    }
}

// MARK: - 关于子页

struct AboutPage: View {
    var body: some View {
        ZStack {
            WebConsoleBackground()
            ScrollView {
                VStack(spacing: 12) {
                    aboutCard {
                        aboutRow(label: "版本", value: appVersion)
                        aboutDivider
                        Link(destination: URL(string: APIConfig.siteBaseURL)!) {
                            HStack {
                                Text("打开控车网页版")
                                    .font(.system(size: 13))
                                    .foregroundStyle(WebTheme.txt)
                                Spacer()
                                Image(systemName: "safari")
                                    .font(.system(size: 13))
                                    .foregroundStyle(WebTheme.blue)
                            }
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        aboutDivider
                        aboutRow(label: "联系站主", value: "QQ \(APIConfig.ownerContactQQ)")
                    }
                    Text("原生 SwiftUI 应用 · 车况与控车链路同官网 App · 数据来自站主自有后端")
                        .font(.system(size: 10.5))
                        .foregroundStyle(WebTheme.faint)
                        .multilineTextAlignment(.center)
                }
                .padding(16)
            }
        }
        .hideScrollBackground()
        .inlineTitle("关于")
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func aboutCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(WebTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(WebTheme.border, lineWidth: 1))
    }

    private func aboutRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(WebTheme.txt)
            Spacer()
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(WebTheme.muted)
        }
        .padding(.vertical, 10)
    }

    private var aboutDivider: some View {
        Rectangle().fill(WebTheme.border.opacity(0.5)).frame(height: 0.5)
    }
}
