import SwiftUI
import CarCore

/// 蓝牙车钥匙 — 主界面（Dock「蓝牙钥匙」标签）
struct CarKeyView: View {
    @StateObject private var manager = BLECarKeyManager.shared
    @StateObject private var store = CarKeyStore.shared
    @State private var confirmAction: CarKeyAction?

    var body: some View {
        NavStack {
            ZStack {
                WebConsoleBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        statusCard
                        if manager.connectionState == .connected {
                            controlSection
                            infoSection
                        } else {
                            scanSection
                        }
                        logSection
                        Spacer(minLength: 24)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
            }
            .inlineTitle("蓝牙钥匙")
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    NavigationLink {
                        CarKeySettingsView()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(WebTheme.blue)
                            .accessibilityLabel("蓝牙钥匙设置")
                    }
                }
            }
        }
        .tint(WebTheme.blue)
        .alert(item: $confirmAction) { action in
            Alert(
                title: Text("确认\(action.title)？"),
                message: Text("该操作会向车辆发送「\(action.title)」指令，请确认周边安全。"),
                primaryButton: .destructive(Text("确认发送")) { manager.send(action) },
                secondaryButton: .cancel(Text("取消"))
            )
        }
    }

    // MARK: 状态卡

    private var statusCard: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                Text(manager.connectionState.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.primary)
                Spacer()
                if manager.connectionState == .connected {
                    Text(manager.connectedName)
                        .font(.system(size: 13))
                        .foregroundStyle(WebTheme.muted)
                } else if manager.bluetoothState != .poweredOn {
                    Text("请开启蓝牙")
                        .font(.system(size: 13))
                        .foregroundStyle(WebTheme.red)
                }
            }
            if manager.connectionState == .connected {
                HStack(spacing: 24) {
                    metric(title: "信号", value: "\(manager.rssi) dBm")
                    metric(title: "估算距离", value: String(format: "%.1f m", manager.distance))
                    metric(title: "PKE", value: manager.pkeState.rawValue)
                }
            }
        }
        .padding(14)
        .background(cardBg)
        .accessibilityElement(children: .combine)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
            Text(title).font(.system(size: 11)).foregroundStyle(WebTheme.muted)
        }
    }

    private var dotColor: Color {
        switch manager.connectionState {
        case .connected: return WebTheme.green
        case .scanning, .connecting: return WebTheme.amber
        case .failed: return WebTheme.red
        default: return WebTheme.muted
        }
    }

    // MARK: 扫描 / 设备列表

    private var scanSection: some View {
        VStack(spacing: 12) {
            Button {
                if manager.connectionState == .scanning { manager.stopScan() }
                else { manager.startScan() }
            } label: {
                Label(manager.connectionState == .scanning ? "停止扫描" : "开始扫描",
                      systemImage: manager.connectionState == .scanning ? "stop.circle.fill" : "radiowaves.left")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(WebTheme.blue)
                    .foregroundStyle(.white)
                    .font(.system(size: 16, weight: .semibold))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel(manager.connectionState == .scanning ? "停止扫描" : "开始扫描")

            if manager.discovered.isEmpty {
                EmptyStateView(systemImage: "wave.3.right",
                               title: "附近暂无设备",
                               message: "点击「开始扫描」，靠近车辆蓝牙模块后等待出现。")
            } else {
                ForEach(manager.discovered) { dev in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(dev.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.primary)
                            Text("RSSI \(dev.rssi) dBm").font(.system(size: 12)).foregroundStyle(WebTheme.muted)
                        }
                        Spacer()
                        if dev.isBonded {
                            Text("已绑定").font(.system(size: 12)).foregroundStyle(WebTheme.green)
                        }
                        Button("连接") { manager.connect(dev) }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WebTheme.blue)
                            .accessibilityLabel("连接 \(dev.name)")
                    }
                    .padding(12)
                    .background(cardBg)
                }
            }
        }
    }

    // MARK: 控车

    private var controlSection: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(CarKeyAction.allCases) { action in
                    Button {
                        if action.isDangerous { confirmAction = action }
                        else { manager.send(action) }
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: action.symbol)
                                .font(.system(size: 26))
                            Text(action.title).font(.system(size: 14, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(action.isDangerous ? WebTheme.red.opacity(0.12) : WebTheme.blue.opacity(0.1))
                        .foregroundStyle(action.isDangerous ? WebTheme.red : WebTheme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel(action.title)
                }
            }
            HStack(spacing: 12) {
                Button {
                    manager.bondCurrent()
                } label: {
                    Label("绑定此设备", systemImage: "link.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("绑定此设备")
                Button {
                    manager.disconnect()
                } label: {
                    Label("断开", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.secondarySystemBackground))
                        .foregroundStyle(WebTheme.muted)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel("断开连接")
            }
        }
    }

    // MARK: 信息

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("最近回包").font(.system(size: 12, weight: .semibold)).foregroundStyle(WebTheme.muted)
            Text(manager.lastResponse.isEmpty ? "—" : manager.lastResponse.uppercased())
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBg)
    }

    // MARK: 日志

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("通信日志").font(.system(size: 12, weight: .semibold)).foregroundStyle(WebTheme.muted)
            if manager.logs.isEmpty {
                Text("暂无").font(.system(size: 12)).foregroundStyle(WebTheme.muted)
            } else {
                ForEach(Array(manager.logs.suffix(8).enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(size: 11, design: .monospaced)).foregroundStyle(WebTheme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBg)
    }

    private var cardBg: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color(.secondarySystemBackground))
            .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}
