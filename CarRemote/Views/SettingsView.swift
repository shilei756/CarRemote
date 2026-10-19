import SwiftUI
import CarCore
import UIKit

/// 我的（账号 / 防误触 / 语音开关 / 圈子资料 / 关于）
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var settings: AppSettings = SharedStore.loadSettings()
    @State private var showLogoutConfirm = false
    @State private var showWhitelist = false
    // 折叠状态：账号 / 外观 / 小组件默认收起（反馈：我的页太长的，先看核心信息）
    @State private var accountExpanded = false
    @State private var appearanceExpanded = false
    @State private var widgetExpanded = false
    // 折叠状态：高危操作与 Siri 语音默认收起（反馈 #7）
    @State private var confirmExpanded = false
    @State private var siriExpanded = false
    @State private var appTheme: AppTheme = SharedStore.loadAppTheme()
    // 服务器地址（仅站主可见）
    @State private var serverDraft: String = APIConfig.siteBaseURL
    @State private var serverSavedTip = false

    var body: some View {
        NavStack {
            Form {
                accountSection
                appearanceSection
                widgetSection
                confirmSection
                siriSection
                // 服务器地址：仅站主账号可见（换域名免发版）
                if appState.credentials?.phone == APIConfig.ownerPhone {
                    serverSection
                }
                // 网页版 applyAdminEntry：非管理员不显示管理入口
                if appState.isAdminUser {
                    adminSection
                }
                clubProfileSection
                aboutSection
            }
            .hideScrollBackground()
            .background(WebConsoleBackground())
            .inlineTitle("我的")
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

    // MARK: - 服务器地址（仅站主）

    private var serverSection: some View {
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
        } header: {
            Text("服务器地址")
        } footer: {
            Text("只有站主账号（\(APIConfig.ownerPhone)）能看到此项。换域名/迁移后端时在此填入新地址即可，无需重新出包。注意：新域名必须仍指向同一套数据库，否则登录态、卡密、白名单都会失效。")
        }
    }

    // MARK: - 账号（默认折叠）

    private var accountSection: some View {
        Section {
            DisclosureGroup(isExpanded: $accountExpanded) {
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
            } label: {
                Text("账号")
            }
        } footer: {
            Text("登录手机号、授权状态与退出登录入口")
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

    // MARK: - 车型外观 / 主题（默认折叠）

    private var appearanceSection: some View {
        Section {
            DisclosureGroup(isExpanded: $appearanceExpanded) {
                Picker("仪表盘车型", selection: $settings.carModelStyle) {
                    ForEach(CarModelStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .compatOnChange(of: settings.carModelStyle) { newStyle in
                    // 油箱容积联动车型默认值（网页版 CAR_MODELS.tank：切换车型时油量百分比基准随之变化）
                    settings.tankCapacityL = newStyle.tankCapacityL
                    saveSettings()
                }
                Picker("主题", selection: $appTheme) {
                    Text("浅色（经典）").tag(AppTheme.light)
                    Text("夜间").tag(AppTheme.dark)
                }
                .compatOnChange(of: appTheme) { newValue in
                    ThemeManager.shared.set(newValue)
                }
                // 油箱总容量（油量百分比/进度条基准）
                HStack {
                    Text("油箱总容量")
                    Spacer()
                    TextField("50", value: Binding(
                        get: { settings.tankCapacityL },
                        set: { newValue in
                            let clamped = min(max(newValue, 20), 120)
                            settings.tankCapacityL = clamped
                            saveSettings()
                        }
                    ), format: .number.precision(.fractionLength(0...1)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    Text("L")
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text("外观")
            }
        } footer: {
            Text("切换车型会同步油箱容积基准（逸动PLUS 53L、UNI-V 51L、CS75PLUS 58L、UNI-K 56L、CS75 20款 58L），油量百分比与油条按此换算；下方仍可手动修改")
        }
    }

    // MARK: - 小组件按钮自定义（默认折叠）
    private var widgetSection: some View {
        Section {
            DisclosureGroup(isExpanded: $widgetExpanded) {
                ForEach(0..<5, id: \.self) { index in
                    Picker("按钮 \(index + 1)", selection: widgetCommandBinding(index)) {
                        ForEach(CarCommand.allCases, id: \.self) { command in
                            Text(command.displayName).tag(command.rawValue)
                        }
                    }
                }
            } label: {
                Text("小组件按钮")
            }
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
        .compatOnChange(of: settings.clubNick) { _ in saveSettings() }
        .compatOnChange(of: settings.clubAvatar) { _ in saveSettings() }
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
