import SwiftUI
import CarCore
import UIKit

/// 我的（账号 / 防误触 / 语音开关 / 圈子资料 / 关于）
struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var settings: AppSettings = SharedStore.loadSettings()
    @State private var showLogoutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                appearanceSection
                confirmSection
                siriSection
                clubProfileSection
                aboutSection
            }
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
        guard let cardStatus = appState.cardStatus else { return "校验中" }
        if cardStatus.isRegular { return "正式用户" }
        if cardStatus.todayOK { return "体验中（今日有效）" }
        return "未授权"
    }

    // MARK: - 车型外观

    private var appearanceSection: some View {
        Section {
            Picker("仪表盘车型", selection: $settings.carModelStyle) {
                ForEach(CarModelStyle.allCases, id: \.self) { style in
                    Text(style.rawValue).tag(style)
                }
            }
            .onChange(of: settings.carModelStyle) { _, _ in
                saveSettings()
            }
        } header: {
            Text("外观")
        } footer: {
            Text("仅影响主界面车辆示意图的造型")
        }
    }

    // MARK: - 防误触

    private var confirmSection: some View {
        Section {
            ForEach(CarCommand.allCases, id: \.self) { command in
                Toggle(isOn: confirmBinding(for: command)) {
                    Label(command.displayName, systemImage: command.sfSymbol)
                }
            }
        } header: {
            Text("高危操作二次确认")
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

    // MARK: - Siri 语音开关

    private var siriSection: some View {
        Section {
            ForEach(CarCommand.allCases, id: \.self) { command in
                Toggle(isOn: siriBinding(for: command)) {
                    Label(command.displayName, systemImage: command.sfSymbol)
                }
            }
        } header: {
            Text("Siri 语音控制")
        } footer: {
            Text("关闭后，对应指令不再响应语音与小组件按钮。语音短语如：「用远程控车解锁车辆」")
        }
    }

    private func siriBinding(for command: CarCommand) -> Binding<Bool> {
        Binding(
            get: { settings.siriAllows(command: command) },
            set: { _ in
                settings.toggleSiri(command: command)
                saveSettings()
            }
        )
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
