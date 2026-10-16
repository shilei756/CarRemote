import SwiftUI
import CarCore

/// 主界面：五个标签（控车 / 圈子 / 油耗 / 维保 / 我的）
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            DashboardView(appState: appState)
                .tabItem {
                    Label("控车", systemImage: "car.circle.fill")
                }
            ClubView(appState: appState)
                .tabItem {
                    Label("圈子", systemImage: "bubble.left.and.bubble.right.fill")
                }
            FuelTrackerView(appState: appState)
                .tabItem {
                    Label("油耗", systemImage: "fuelpump.fill")
                }
            MaintenanceView(appState: appState)
                .tabItem {
                    Label("维保", systemImage: "wrench.and.screwdriver.fill")
                }
            SettingsView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle.fill")
                }
        }
        .tint(.accentColor)
    }
}

/// 控车主界面：车况仪表盘 + 快捷控车
struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: DashboardViewModel

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(appState: appState))
    }

    private var settings: AppSettings { SharedStore.loadSettings() }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let errorMessage = appState.errorMessage {
                        errorBanner(errorMessage)
                    }
                    carHeader
                    if let status = appState.status {
                        carVisual(status: status)
                        stateFlagsCard(status: status)
                        primaryControls
                        statusTiles(status: status)
                        tireCard(status: status)
                        if status.location != nil {
                            locateButton
                        }
                    } else {
                        EmptyStateView(
                            systemImage: "antenna.radiowaves.left.and.right",
                            title: appState.isRefreshing ? "正在获取车况…" : "暂无车况数据",
                            message: appState.isRefreshing ? "" : "下拉刷新，或点击右上角按钮重新获取"
                        )
                    }
                    Spacer(minLength: 24)
                }
                .padding(16)
            }
            .background(Color(.systemBackground))
            .navigationTitle(appState.carName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await appState.refreshStatus() }
                    } label: {
                        if appState.isRefreshing {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .accessibilityLabel("刷新车况")
                    .disabled(appState.isRefreshing)
                }
            }
            .refreshable {
                await appState.refreshStatus()
            }
            .toast(viewModel.toast)
            .onChange(of: viewModel.toast) { _, newValue in
                if newValue != nil {
                    Task {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        viewModel.toast = nil
                    }
                }
            }
            .sheet(isPresented: $viewModel.showMoreControls) {
                MoreControlsSheet(viewModel: viewModel)
            }
            .alert("确认执行", isPresented: confirmBinding) {
                Button("取消", role: .cancel) { viewModel.cancelPending() }
                Button("确认执行", role: .destructive) { viewModel.confirmPending() }
            } message: {
                Text(confirmMessage)
            }
        }
    }

    // MARK: - 车辆头部

    private var carHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.carName)
                    .font(.title3.bold())
                Text("更新于 \(updatedTimeText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: settings.carModelStyle.sfSymbol)
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }

    private var updatedTimeText: String {
        guard let date = appState.statusUpdatedAt else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    // MARK: - 车辆可视化

    private func carVisual(status: CarStatus) -> some View {
        SectionCard {
            CarVisualView(style: settings.carModelStyle, isUnlocked: status.doorUnlocked)
                .padding(.horizontal, 8)
            HStack {
                Text(status.engineRunning ? "发动机已启动" : "发动机熄火")
                    .font(.caption.bold())
                    .foregroundStyle(status.engineRunning ? Color.red : Color.secondary)
                Spacer()
                Text(status.doorUnlocked ? "车门已解锁" : "车门已锁止")
                    .font(.caption.bold())
                    .foregroundStyle(status.doorUnlocked ? Color.orange : Color.green)
            }
        }
    }

    // MARK: - 状态旗标

    private func stateFlagsCard(status: CarStatus) -> some View {
        SectionCard(title: "车辆状态") {
            let flags = status.stateFlags.flags
            if flags.isEmpty {
                FlagChip(text: "一切正常", systemImage: "checkmark.shield.fill", color: .green)
            } else {
                FlowTagLayout(spacing: 8) {
                    ForEach(Array(flags.enumerated()), id: \.offset) { _, flag in
                        FlagChip(
                            text: flag.text,
                            systemImage: flagSystemImage(key: flag.key),
                            color: flagColor(key: flag.key)
                        )
                    }
                }
            }
        }
    }

    private func flagSystemImage(key: String) -> String {
        switch key {
        case "door": return "lock.open.fill"
        case "win": return "wind"
        case "engine": return "flame.fill"
        default: return "checkmark.shield.fill"
        }
    }

    private func flagColor(key: String) -> Color {
        switch key {
        case "door": return .orange
        case "win": return .blue
        case "engine": return .red
        default: return .green
        }
    }

    // MARK: - 主控区

    private var primaryControls: some View {
        SectionCard(title: "快捷控车") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4),
                spacing: 20
            ) {
                ForEach(CarCommand.primaryCommands, id: \.self) { command in
                    ControlButtonView(
                        command: command,
                        isPrimary: true,
                        isExecuting: viewModel.executingCommand == command
                    ) {
                        viewModel.execute(command)
                    }
                }
            }
            .padding(.vertical, 8)

            Button {
                viewModel.showMoreControls = true
            } label: {
                HStack {
                    Image(systemName: "square.grid.2x2.fill")
                    Text("更多控车")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .font(.subheadline.bold())
                .padding(12)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("更多控车指令")
        }
    }

    // MARK: - 车况数值

    private func statusTiles(status: CarStatus) -> some View {
        SectionCard(title: "车况数据") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                spacing: 12
            ) {
                StatusTile(
                    title: "剩余续航",
                    value: CarStatus.format(status.remainingRangeKm),
                    unit: "km",
                    systemImage: "road.lanes",
                    tint: .green
                )
                StatusTile(
                    title: "剩余油量",
                    value: CarStatus.format(status.fuelLeftLiters),
                    unit: "L",
                    systemImage: "fuelpump",
                    tint: .orange
                )
                StatusTile(
                    title: "总里程",
                    value: CarStatus.format(status.totalOdometerKm),
                    unit: "km",
                    systemImage: "speedometer"
                )
                StatusTile(
                    title: "电瓶电压",
                    value: CarStatus.format(status.batteryVoltage),
                    unit: "V",
                    systemImage: "bolt.fill",
                    tint: voltageColor(status.batteryVoltage)
                )
                StatusTile(
                    title: "车外温度",
                    value: CarStatus.format(status.vehicleTempC),
                    unit: "°C",
                    systemImage: "thermometer.medium"
                )
                StatusTile(
                    title: "空调设定",
                    value: CarStatus.format(status.acTempC),
                    unit: "°C",
                    systemImage: "snowflake"
                )
            }
        }
    }

    /// 电瓶电压告警：低于 11.8V 或高于 14.8V 视为异常（燃油车常见区间）
    private func voltageColor(_ voltage: Double?) -> Color {
        guard let voltage else { return .accentColor }
        if voltage < 11.8 || voltage > 14.8 { return .red }
        return .green
    }

    // MARK: - 胎压

    private func tireCard(status: CarStatus) -> some View {
        SectionCard(title: "胎压监测") {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2),
                spacing: 12
            ) {
                ForEach(status.tirePressures, id: \.label) { tire in
                    StatusTile(
                        title: tire.label + "胎压",
                        value: CarStatus.format(tire.valueKPa),
                        unit: "kPa",
                        systemImage: tire.isLow ? "exclamationmark.tirepressure" : "circle.grid.cross",
                        tint: tire.isLow ? .red : .accentColor
                    )
                }
            }
            if status.tirePressures.contains(where: \.isLow) {
                Label("有轮胎胎压偏低，建议检查", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - 定位

    private var locateButton: some View {
        Button {
            viewModel.navigateToCar()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                Text("导航到车辆位置")
                    .font(.subheadline.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(14)
            .background(Color.accentColor.opacity(0.14))
            .foregroundStyle(.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("导航到车辆位置")
    }

    // MARK: - 错误横幅

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                appState.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 确认弹窗

    private var confirmBinding: Binding<Bool> {
        Binding(
            get: { viewModel.pendingConfirm != nil },
            set: { if !$0 { viewModel.cancelPending() } }
        )
    }

    private var confirmMessage: String {
        guard let command = viewModel.pendingConfirm else { return "" }
        return "「\(command.displayName)」属于高危操作，确认要通过远程指令执行吗？"
    }
}

/// 更多控车面板
struct MoreControlsSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4),
                    spacing: 20
                ) {
                    ForEach(CarCommand.extraCommands, id: \.self) { command in
                        ControlButtonView(
                            command: command,
                            isExecuting: viewModel.executingCommand == command
                        ) {
                            viewModel.execute(command)
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("更多控车")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// 流式标签布局（状态旗标换行）
struct FlowTagLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x = 0.0, y = 0.0, rowHeight = 0.0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight = 0.0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
