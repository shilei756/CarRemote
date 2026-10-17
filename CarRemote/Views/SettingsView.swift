import SwiftUI
import CarCore
import UIKit

/// 我的（账号 / 防误触 / 语音开关 / 圈子资料 / 关于）
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var settings: AppSettings = SharedStore.loadSettings()
    @State private var showLogoutConfirm = false
    @State private var showWhitelist = false
    // 折叠状态：高危操作与 Siri 语音默认收起（反馈 #7）
    @State private var confirmExpanded = false
    @State private var siriExpanded = false
    @State private var appTheme: AppTheme = SharedStore.loadAppTheme()

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                appearanceSection
                widgetSection
                confirmSection
                siriSection
                // 网页版 applyAdminEntry：非管理员不显示管理入口
                if appState.isAdminUser {
                    adminSection
                }
                clubProfileSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(WebConsoleBackground())
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .alert("退出登录", isPresented: $showLogoutConfirm) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) {
                    appState.logout()
                }
            } message: {
                Text("退出后需要重新输入手机号与控车码登录，本地记录不会丢失。")
            }
            .sheet(isPresented: $showWhitelist) {
                WhitelistView()
                    .environmentObject(appState)
            }
            .task {
                // 兜底：确保管理员身份已探测（决定入口显隐）
                if !appState.isAdminUser {
                    await appState.refreshAdminRole()
                }
            }
        }
    }

    // MARK: - 账号

    private var accountSection: some View {
        Section {
            HStack {
                Text("手机号")
                Spacer()
                Text(appState.credentials?.maskedPhone ?? "--")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("授权状态")
                Spacer()
                Text(cardStatusText)
                    .foregroundStyle(.secondary)
            }
            if let cardStatus = appState.cardStatus, let expiry = cardStatus.expiryText {
                HStack {
                    Text("有效期")
                    Spacer()
                    Text(expiry)
                        .foregroundStyle(.secondary)
                }
            }
            Button("退出登录", role: .destructive) {
                showLogoutConfirm = true
            }
        } header: {
            Text("账号")
        }
    }

    private var cardStatusText: String {
        // 站主 = 开发者，最高权限
        if appState.credentials?.phone == APIConfig.ownerPhone { return "开发者 · 最高权限" }
        guard let cardStatus = appState.cardStatus else { return "校验中" }
        if cardStatus.isRegular { return "正式用户" }
        if cardStatus.todayOK { return "体验用户（今日有效）" }
        if cardStatus.experience {
            if let hours = cardStatus.expiryHours {
                return "体验用户（剩余 \(String(format: "%.0f", hours)) 小时）"
            }
            return "体验用户"
        }
        return "未授权"
    }

    // MARK: - 车型外观 / 主题

    private var appearanceSection: some View {
        Section {
            Picker("仪表盘车型", selection: $settings.carModelStyle) {
                ForEach(CarModelStyle.allCases, id: \.self) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .onChange(of: settings.carModelStyle) { _, _ in
                saveSettings()
            }
            Picker("主题", selection: $appTheme) {
                Text("浅色（经典）").tag(AppTheme.light)
                Text("夜间").tag(AppTheme.dark)
            }
            .onChange(of: appTheme) { _, newValue in
                ThemeManager.shared.set(newValue)
            }
        } header: {
            Text("外观")
        } footer: {
            Text("车型仅影响主界面车辆示意图；夜间主题同网页版暗色配色")
        }
    }

    // MARK: - 小组件按钮自定义

    private var widgetSection: some View {
        Section {
            ForEach(0..<5, id: \.self) { index in
                Picker("按钮 \(index + 1)", selection: widgetCommandBinding(index)) {
                    ForEach(CarCommand.allCases, id: \.self) { command in
                        Text(command.displayName).tag(command.rawValue)
                    }
                }
            }
        } header: {
            Text("小组件按钮")
        } footer: {
            Text("桌面小组件底部的 5 个控车按钮，点一下直接执行（不打开 App）。改完回到桌面等几秒自动刷新。")
        }
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

    // MARK: - 防误触（默认折叠）

    private var confirmSection: some View {
        Section {
            DisclosureGroup(isExpanded: $confirmExpanded) {
                ForEach(CarCommand.allCases, id: \.self) { command in
                    Toggle(isOn: confirmBinding(for: command)) {
                        Label(command.displayName, systemImage: command.sfSymbol)
                    }
                }
            } label: {
                Text("高危操作二次确认")
            }
        } footer: {
            Text("开启后，执行开锁 / 闭锁 / 点火 / 熄火等指令前会弹窗确认")
        }
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

    // MARK: - Siri 语音控制（重新设计：一个总开关 + 短语示例，默认折叠）

    private var siriSection: some View {
        Section {
            DisclosureGroup(isExpanded: $siriExpanded) {
                // 常用直达短语示例
                siriPhraseRow("解锁车辆", phrase: "用长安控车解锁车辆")
                siriPhraseRow("锁定车辆", phrase: "用长安控车锁上车")
                siriPhraseRow("查看车况", phrase: "长安控车车况怎么样")
                siriPhraseRow("寻车", phrase: "用长安控车找车")
                siriPhraseRow("空调", phrase: "用长安控车打开 / 关闭空调")
                siriPhraseRow("任意指令", phrase: "用长安控车控制车辆")
            } label: {
                Toggle(isOn: siriMasterBinding) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Siri 语音控制")
                            Text("关闭后所有语音与快捷指令立即失效")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "waveform")
                    }
                }
            }
        } footer: {
            Text("对 Siri 说下表短语即可控车。点火、熄火等高危操作会先向你确认；「控制车辆」可触发任意指令，Siri 会追问要做什么。")
        }
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

    // MARK: - 白名单管理（管理员入口）

    private var adminSection: some View {
        Section {
            Button {
                showWhitelist = true
            } label: {
                HStack {
                    Text("白名单管理")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        } header: {
            Text("管理")
        } footer: {
            Text("查看使用者统计、登录白名单与体验卡密（仅站主 / 管理员可进入）")
        }
    }

    // MARK: - 圈子资料

    private var clubProfileSection: some View {
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
        } header: {
            Text("圈子资料")
        } footer: {
            Text("发布动态时展示的昵称与头像，留空则显示脱敏手机号")
        }
        .onChange(of: settings.clubNick) { _, _ in saveSettings() }
        .onChange(of: settings.clubAvatar) { _, _ in saveSettings() }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text(appVersion)
                    .foregroundStyle(.secondary)
            }
            Link(destination: URL(string: APIConfig.siteBaseURL)!) {
                HStack {
                    Text("打开控车网页版")
                    Spacer()
                    Image(systemName: "safari")
                }
            }
            HStack {
                Text("联系站主")
                Spacer()
                Text("QQ \(APIConfig.ownerContactQQ)")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("关于")
        } footer: {
            Text("原生 SwiftUI 应用 · 车况与控车链路同官网 App · 数据来自站主自有后端")
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func saveSettings() {
        SharedStore.saveSettings(settings)
    }
}
