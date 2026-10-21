import SwiftUI
import CarCore

/// 蓝牙车钥匙 — 设置页（协议参数全部可调，默认值来自逆向还原）
struct CarKeySettingsView: View {
    @ObservedObject private var store = CarKeyStore.shared
    @State private var showReset = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                connectionSection
                pkeSection
                securitySection
                framesSection
                resetSection
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .inlineTitle("蓝牙钥匙设置")
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .alert("恢复默认配置？", isPresented: $showReset) {
            Button("恢复", role: .destructive) { store.resetToDefaults() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将 UUID、指令帧、RSSI 阈值重置为逆向出的默认值，已绑定设备保留。")
        }
    }

    // MARK: 连接参数

    private var connectionSection: some View {
        SectionCard(title: "连接参数", subtitle: "GATT 服务与特征值 UUID（默认来自逆向）") {
            uuidRow("主服务 UUID", text: $store.config.serviceUUID)
            uuidRow("写入特征 UUID", text: $store.config.writeUUID)
            uuidRow("通知特征 UUID", text: $store.config.notifyUUID)
            uuidRow("HID 服务 UUID", text: $store.config.hidServiceUUID)
            uuidRow("HID 写入 UUID", text: $store.config.hidWriteUUID)
            uuidRow("HID 通知 UUID", text: $store.config.hidNotifyUUID)
        }
    }

    private func uuidRow(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(WebTheme.muted)
            TextField("UUID", text: text)
                .font(.system(size: 13, design: .monospaced))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: 无钥匙进入

    private var pkeSection: some View {
        SectionCard(title: "无钥匙进入（RSSI 判定）",
                    subtitle: "靠近（信号强）自动解锁，远离（信号弱）自动上锁。前台有效。") {
            Toggle("靠近自动解锁", isOn: $store.config.autoUnlock)
            Toggle("远离自动上锁", isOn: $store.config.autoLock)
            rssiStepper(title: "解锁阈值", value: $store.config.unlockRSSI, hint: "大于此值解锁（越近数值越大）")
            rssiStepper(title: "上锁阈值", value: $store.config.lockRSSI, hint: "小于此值上锁（越远数值越小）")
            rssiStepper(title: "1 米参考 RSSI", value: $store.config.measurePower, hint: "距离估算基准")
        }
    }

    private func rssiStepper(title: String, value: Binding<Int>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).font(.system(size: 14)).foregroundStyle(Color.primary)
                Spacer()
                Stepper(value: value, in: -120...0, step: 1) {
                    Text("\(value.wrappedValue) dBm").font(.system(size: 14, weight: .medium)).foregroundStyle(WebTheme.blue)
                }
            }
            Text(hint).font(.system(size: 11)).foregroundStyle(WebTheme.muted)
        }
        .padding(.vertical, 2)
    }

    // MARK: 安全

    private var securitySection: some View {
        SectionCard(title: "安全", subtitle: "部分车型需先验证操作密码") {
            SecureField("操作密码（可选）", text: $store.config.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: 指令帧

    private var framesSection: some View {
        SectionCard(title: "指令帧（hex）",
                    subtitle: "每个动作下发的 hex 帧，默认值为逆向出的 7X 序列样式，按实车验证微调。") {
            ForEach(CarKeyAction.allCases) { action in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: action.symbol).foregroundStyle(WebTheme.blue)
                        Text(action.title).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.primary)
                        if action.isDangerous {
                            Text("高危").font(.system(size: 10)).foregroundStyle(WebTheme.red)
                        }
                    }
                    TextField("hex 帧", text: frameBinding(action))
                        .font(.system(size: 13, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func frameBinding(_ action: CarKeyAction) -> Binding<String> {
        Binding(
            get: { store.config.frames[action.rawValue] ?? action.defaultFrame },
            set: { store.config.frames[action.rawValue] = $0 }
        )
    }

    // MARK: 恢复

    private var resetSection: some View {
        Button(role: .destructive) {
            showReset = true
        } label: {
            Label("恢复逆向默认配置", systemImage: "arrow.counterclockwise")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.secondarySystemBackground))
                .foregroundStyle(WebTheme.red)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("恢复逆向默认配置")
    }

    // MARK: 卡片容器

    private var cardBg: some View {
        RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground))
    }
}

private struct SectionCard<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
                Text(subtitle).font(.system(size: 11)).foregroundStyle(WebTheme.muted)
            }
            content()
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
        }
    }
}
