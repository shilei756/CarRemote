import SwiftUI
import CarCore

/// 主界面：五个标签（控车 / 圈子 / 油耗 / 维保 / 我的）
/// 样式照搬网页版控制台（浅色 + 白卡 + 樱花花瓣 + 浮动车图）
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var tabRouter = TabRouter.shared

    var body: some View {
        TabView(selection: $tabRouter.selectedTab) {
            DashboardView(appState: appState)
                .tabItem {
                    Label("控车", systemImage: "car.circle.fill")
                }
                .tag(TabRouter.Tab.control)
            ClubView(appState: appState)
                .tabItem {
                    Label("圈子", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(TabRouter.Tab.club)
            FuelTrackerView(appState: appState)
                .tabItem {
                    Label("油耗", systemImage: "fuelpump.fill")
                }
                .tag(TabRouter.Tab.fuel)
            MaintenanceView(appState: appState)
                .tabItem {
                    Label("维保", systemImage: "wrench.and.screwdriver.fill")
                }
                .tag(TabRouter.Tab.maintenance)
            SettingsView()
                .tabItem {
                    Label("我的", systemImage: "person.crop.circle.fill")
                }
                .tag(TabRouter.Tab.profile)
        }
        .tint(WebTheme.blue)
    }
}

/// 控车主界面：照搬网页版控制台结构
/// header（车名+状态点） → 浮动车图 → 车况卡 → 快捷控车 → 更多指令 → 定位卡
struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: DashboardViewModel

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(appState: appState))
    }

    @State private var showWallpaperSheet = false

    private var settings: AppSettings { SharedStore.loadSettings() }

    /// 油箱容积估算（长安逸动PLUS/UNI-V 约 50L），用于油量百分比进度条
    private let tankCapacityL = 50.0

    var body: some View {
        NavigationStack {
            ZStack {
                WebConsoleBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        if let errorMessage = appState.errorMessage {
                            errorBanner(errorMessage)
                        }
                        if let status = appState.status {
                            carStage(status: status)
                            vehicleInfoCard(status: status)
                            quickControlsCard
                            moreControlsCard
                            if status.location != nil {
                                locationCard(status: status)
                            }
                            moreToolsCard
                        } else {
                            loadingOrEmpty
                        }
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                }
                .refreshable {
                    await appState.refreshStatus()
                    viewModel.loadLocation()
                }
                .task {
                    viewModel.loadLocation()
                    if viewModel.acMode == .new {
                        await viewModel.loadACRemainingDays()
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 6) {
                        Text(appState.carName)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(WebTheme.txt)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // 网页版 .icon-round 圆形刷新钮
                    Button {
                        Task { await appState.refreshStatus() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(WebTheme.card)
                                .frame(width: 34, height: 34)
                            Circle()
                                .strokeBorder(WebTheme.border, lineWidth: 1)
                                .frame(width: 34, height: 34)
                            if appState.isRefreshing {
                                ProgressView()
                                    .scaleEffect(0.75)
                                    .tint(WebTheme.muted)
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(WebTheme.muted)
                            }
                        }
                    }
                    .accessibilityLabel("刷新车况")
                    .disabled(appState.isRefreshing)
                }
            }
            .toolbarBackground(.automatic, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(isPresented: $viewModel.showACQR) {
                ACQRScanSheet {
                    // 开通成功：刷新剩余天数展示
                    Task { await viewModel.loadACRemainingDays() }
                }
                .environmentObject(appState)
            }
            .sheet(isPresented: $viewModel.showHistoryActions) {
                ControlHistorySheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $viewModel.showMessages) {
                MessageHistorySheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $viewModel.showTrips) {
                TripHistorySheet()
                    .environmentObject(appState)
            }
            .sheet(item: $viewModel.showEmbed) { target in
                EmbedWebSheet(key: target.key)
                    .environmentObject(appState)
            }
            .sheet(isPresented: $viewModel.showWhitelist) {
                WhitelistView()
                    .environmentObject(appState)
            }
            .alert("确认执行", isPresented: confirmBinding) {
                Button("取消", role: .cancel) { viewModel.cancelPending() }
                Button("确认执行", role: .destructive) { viewModel.confirmPending() }
            } message: {
                Text(confirmMessage)
            }
        }
    }

    private var loadingOrEmpty: some View {
        Group {
            if appState.isRefreshing {
                VStack(spacing: 14) {
                    ProgressView()
                        .tint(WebTheme.blue)
                    Text("正在获取车况…")
                        .font(.system(size: 13))
                        .foregroundStyle(WebTheme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
            } else {
                EmptyStateView(
                    systemImage: "antenna.radiowaves.left.and.right",
                    title: "暂无车况数据",
                    message: "下拉刷新，或点击右上角按钮重新获取"
                )
            }
        }
    }

    // MARK: - 浮动车图（网页版 car-stage：车图浮动 + 椭圆阴影 + 车况标签 + 四轮胎压）

    private func carStage(status: CarStatus) -> some View {
        VStack(spacing: 0) {
            CarVisualView(style: settings.carModelStyle, isUnlocked: status.doorUnlocked)
                .padding(.horizontal, 20)
                .carFloat()

            // 椭圆阴影（网页版 .car-shadow：径向渐变椭圆呼吸）
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.55), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 60
                    )
                )
                .frame(width: 190, height: 12)
                .padding(.top, -4)
                .opacity(0.9)

            // 车况标签（网页版 carStateTags）
            let flags = status.stateFlags.flags
            if !flags.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(flags.enumerated()), id: \.offset) { _, flag in
                        FlagChip(
                            text: flag.text,
                            systemImage: flagSystemImage(key: flag.key),
                            color: flagColor(key: flag.key)
                        )
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.top, 4)
    }

    /// 胎压小标签（网页版 .tpv：白底圆角小签 + 等宽数字，min-width 27px）
    private func tireBadge(_ tire: TirePressure, label: String) -> some View {
        Text(tire.valueKPa.map { "\(Int($0.rounded()))" } ?? "--")
            .font(.system(size: 10.5, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tire.isLow ? WebTheme.red : WebTheme.txt)
            .frame(minWidth: 27)
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .background(tire.isLow ? WebTheme.red.opacity(0.06) : WebTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(tire.isLow ? WebTheme.red.opacity(0.45) : WebTheme.border, lineWidth: 1)
            )
            .shadow(color: Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.1), radius: 4, x: 0, y: 1)
            .accessibilityLabel("\(label)胎压 \(tire.valueKPa.map { "\(Int($0.rounded())) 千帕" } ?? "无数据")")
    }

    // MARK: - 车况卡（网页版 user-info-container：油量条 + 续航 + 里程 + 温度 + 电瓶条）

    private func vehicleInfoCard(status: CarStatus) -> some View {
        SectionCard(sakura: false) {
            HStack(alignment: .top, spacing: 12) {
                // 左列：油量/续航/里程/温度/电瓶（网页版 card 左列）
                VStack(spacing: 10) {
                    // 第一行：油量 + 续航
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "fuelpump.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(WebTheme.amber)
                        Text(CarStatus.format(status.fuelLeftLiters))
                            .font(.system(size: 16, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.txt)
                        Text("L")
                            .font(.system(size: 11))
                            .foregroundStyle(WebTheme.faint)
                        Text("\(fuelPercent(status.fuelLeftLiters))%")
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.muted)
                        Spacer()
                        Text(CarStatus.format(status.remainingRangeKm))
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.txt)
                        Text("km 续航")
                            .font(.system(size: 10))
                            .foregroundStyle(WebTheme.faint)
                    }
                    // 油量条（网页版 .ftrack）
                    WebTrack(
                        fraction: (status.fuelLeftLiters ?? 0) / tankCapacityL,
                        fill: LinearGradient(colors: [WebTheme.amber, WebTheme.amber.opacity(0.7)], startPoint: .leading, endPoint: .trailing),
                        height: 5
                    )
                    // 总里程
                    HStack(spacing: 4) {
                        Text("总里程")
                            .font(.system(size: 11))
                            .foregroundStyle(WebTheme.muted)
                        Text(CarStatus.format(status.totalOdometerKm) + " km")
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.txt)
                        Spacer()
                    }
                    // 上次行程里程 / 油耗（网页版 igniteCumulativeMileage / igniteCumulativeOil）
                    if status.lastTripKm != nil || status.lastTripOilLiters != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "road.lanes")
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.purple)
                            Text("上次行程")
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.muted)
                            Text(CarStatus.format(status.lastTripKm) + " km")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                            Text("·")
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.faint)
                            Text("油耗")
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.muted)
                            Text(CarStatus.format(status.lastTripOilLiters) + " L")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                            Spacer()
                        }
                    }
                    // 第二行：温度 + 电瓶
                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "thermometer.medium")
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.blue)
                            Text(CarStatus.format(status.vehicleTempC) + "°C")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(voltageColor(status.batteryVoltage))
                            Text(CarStatus.format(status.batteryVoltage) + "V")
                                .font(.system(size: 11, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(voltageColor(status.batteryVoltage))
                        }
                    }
                    // 电瓶条（网页版 .btrack：11V~15V 区间）
                    WebTrack(
                        fraction: ((status.batteryVoltage ?? 11) - 10.5) / 4.5,
                        fill: LinearGradient(colors: [voltageColor(status.batteryVoltage)], startPoint: .leading, endPoint: .trailing),
                        height: 4
                    )
                    // 空调设定
                    if status.acTempC != nil {
                        HStack(spacing: 4) {
                            Image(systemName: "snowflake")
                                .font(.system(size: 11))
                                .foregroundStyle(WebTheme.blue)
                            Text("空调 \(CarStatus.format(status.acTempC))°C")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(WebTheme.txt)
                            Spacer()
                        }
                    }
                    // 更新时间
                    HStack {
                        Spacer()
                        Text("更新于 \(updatedTimeText)")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.faint)
                    }
                }

                // 右列：俯视小车图 + 四角胎压签（网页版 car_top_real 40x97 居中 + .tpv 四角）
                ZStack {
                    Image("car_car_top")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 97)
                        .opacity(0.9)
                }
                .frame(width: 84, height: 104)
                .overlay(alignment: .topLeading) {
                    tireBadge(status.tirePressures[0], label: "左前")
                }
                .overlay(alignment: .topTrailing) {
                    tireBadge(status.tirePressures[1], label: "右前")
                }
                .overlay(alignment: .bottomLeading) {
                    tireBadge(status.tirePressures[2], label: "左后")
                }
                .overlay(alignment: .bottomTrailing) {
                    tireBadge(status.tirePressures[3], label: "右后")
                }
            }
        }
    }

    private func fuelPercent(_ liters: Double?) -> Int {
        guard let liters else { return 0 }
        return Int(min(max((liters / tankCapacityL) * 100, 0), 100).rounded())
    }

    /// 电瓶电压告警：低于 11.8V 或高于 14.8V 视为异常（燃油车常见区间）
    private func voltageColor(_ voltage: Double?) -> Color {
        guard let voltage else { return WebTheme.green }
        if voltage < 11.8 || voltage > 14.8 { return WebTheme.red }
        return WebTheme.green
    }

    // MARK: - 快捷控车（网页版 quickCard：闪灯/开锁/闭锁/鸣笛，中间两个为描边大钮）

    private var quickControlsCard: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(CarCommand.primaryCommands.enumerated()), id: \.element) { index, command in
                ControlButtonView(
                    command: command,
                    isPrimary: command == .unlockDoor || command == .lockDoor,
                    isExecuting: viewModel.executingCommand == command
                ) {
                    viewModel.execute(command)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .webCard()
    }

    // MARK: - 更多指令（网页版 ctrlCard / moreGrid：5 列网格）

    private var moreControlsCard: some View {
        SectionCard(title: "更多控车", sakura: false) {
            VStack(alignment: .leading, spacing: 10) {
                // 空调模式分段切换（网页版 setAcMode：新版 = 开放平台需扫码开通；官方版 = 直连链路）
                HStack(spacing: 8) {
                    Text("空调控制")
                        .font(.system(size: 10))
                        .foregroundStyle(WebTheme.faint)
                    Picker("空调模式", selection: Binding(
                        get: { viewModel.acMode },
                        set: { viewModel.setACMode($0) }
                    )) {
                        ForEach(ACMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 150)
                    if viewModel.acMode == .new {
                        // 开通剩余日期（已开通才显示）
                        if let days = viewModel.acRemainingDays {
                            Text("剩余 \(days) 天")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(days <= 1 ? WebTheme.red : WebTheme.green)
                        } else {
                            Text("需扫码开通")
                                .font(.system(size: 9))
                                .foregroundStyle(WebTheme.amber)
                        }
                    }
                    Spacer()
                }
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5),
                    spacing: 14
                ) {
                    ForEach(Array(CarCommand.extraCommands.enumerated()), id: \.element) { _, command in
                        CompactControlButton(
                            command: command,
                            isExecuting: viewModel.executingCommand == command
                        ) {
                            viewModel.execute(command)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - 定位卡（网页版 locCard：具体地址 + 城市 + 定位时间 + 紫蓝渐变导航按钮）

    private func locationCard(status: CarStatus) -> some View {
        SectionCard(sakura: false) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(WebTheme.purple.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "location.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(WebTheme.purple)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("车辆位置")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WebTheme.txt)
                    // 主行：官网返回的具体地址（小区/路段），无地址时回退经纬度
                    Text(locationAddressText(status))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WebTheme.txt)
                        .lineLimit(1)
                    // 次行：城市 · 定位时间 · 经纬度
                    Text(locationSubText(status))
                        .font(.system(size: 10))
                        .monospacedDigit()
                        .foregroundStyle(WebTheme.muted)
                        .lineLimit(1)
                }
                Spacer()
                if viewModel.isLoadingLocation {
                    ProgressView()
                        .tint(WebTheme.muted)
                } else {
                    Button {
                        viewModel.loadLocation()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WebTheme.muted)
                            .frame(width: 30, height: 30)
                            .background(WebTheme.card2)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("刷新位置")
                }
                // 网页版 .nav-btn：紫蓝渐变胶囊
                Button {
                    viewModel.navigateToCar()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond")
                            .font(.system(size: 11, weight: .semibold))
                        Text("导航")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .background(WebTheme.navGradient)
                    .clipShape(Capsule())
                    .shadow(color: WebTheme.purple.opacity(0.3), radius: 12, x: 0, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("导航到车辆位置")
            }
        }
    }

    /// 主行地址：优先官网 address；否则「定位中…」/经纬度
    private func locationAddressText(_ status: CarStatus) -> String {
        if let info = viewModel.locationInfo, !info.address.isEmpty {
            return info.address
        }
        if viewModel.isLoadingLocation { return "定位中…" }
        if let location = status.location {
            return String(format: "%.5f, %.5f", location.latitude, location.longitude)
        }
        return "暂无位置信息"
    }

    /// 次行：城市 · 定位时间 · 经纬度
    private func locationSubText(_ status: CarStatus) -> String {
        var parts: [String] = []
        if let info = viewModel.locationInfo {
            if !info.city.isEmpty { parts.append(info.city) }
            if !info.gpsTime.isEmpty { parts.append("定位于 \(info.gpsTime)") }
        }
        if let location = status.location {
            parts.append(String(format: "%.4f, %.4f", location.latitude, location.longitude))
        }
        return parts.isEmpty ? "--" : parts.joined(separator: " · ")
    }

    // MARK: - 更多功能（网页版 moreGrid：11 个磁贴）

    private var moreToolsCard: some View {
        SectionCard(title: "更多功能", sakura: false) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 14
            ) {
                moreToolTile(name: "查询车况", symbol: "arrow.triangle.2.circlepath", color: WebTheme.blue) {
                    Task { await appState.refreshStatus(); viewModel.loadLocation() }
                }
                moreToolTile(name: "操作历史", symbol: "clock.arrow.circlepath", color: WebTheme.amber) {
                    viewModel.showHistoryActions = true
                }
                moreToolTile(name: "消息记录", symbol: "bubble.left.and.text.bubble.right", color: Color(hex: 0x06b6d4)) {
                    viewModel.showMessages = true
                }
                moreToolTile(name: "我的行程", symbol: "road.lanes", color: WebTheme.purple) {
                    viewModel.showTrips = true
                }
                moreToolTile(name: "空调开通", symbol: "qrcode", color: WebTheme.green) {
                    viewModel.showACQR = true
                }
                moreToolTile(name: "车辆状态", symbol: "gauge.with.dots.needle.33percent", color: WebTheme.blue) {
                    viewModel.showEmbed = .vehicleStatus
                }
                moreToolTile(name: "360全景", symbol: "view.360", color: WebTheme.green) {
                    viewModel.showEmbed = .panorama
                }
                moreToolTile(name: "智能维保", symbol: "wrench.and.screwdriver", color: Color(hex: 0xea580c)) {
                    TabRouter.shared.select(.maintenance)
                }
                moreToolTile(name: "背景壁纸", symbol: "photo.on.rectangle.angled", color: Color(hex: 0xdb2777)) {
                    showWallpaperSheet = true
                }
                // 网页版 applyAdminEntry：仅管理员可见管理入口
                if appState.isAdminUser {
                    moreToolTile(name: "白名单管理", symbol: "person.2.shield", color: WebTheme.red) {
                        viewModel.showWhitelist = true
                    }
                }
            }
            .padding(.top, 4)
        }
        .sheet(isPresented: $showWallpaperSheet) {
            WallpaperSheet()
                .environmentObject(appState)
        }
    }

    /// 网页版 tool-tile：圆角方块底 + 彩色图标 + 名称
    private func moreToolTile(name: String, symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(color.opacity(0.10))
                        .frame(width: 42, height: 42)
                    Image(systemName: symbol)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(color)
                }
                Text(name)
                    .font(.system(size: 9.5))
                    .foregroundStyle(WebTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel(name)
        }
        .buttonStyle(.plain)
    }

    // MARK: - 头部与杂项

    private var updatedTimeText: String {
        guard let date = appState.statusUpdatedAt else { return "--" }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
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
        case "door": return WebTheme.amber
        case "win": return WebTheme.blue
        case "engine": return WebTheme.red
        default: return WebTheme.green
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(WebTheme.amber)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.muted)
            Spacer()
            Button {
                appState.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.bold())
                    .foregroundStyle(WebTheme.faint)
            }
        }
        .padding(12)
        .background(WebTheme.amber.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

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

// MARK: - 紧凑型指令按钮（网页版 moreGrid 网格单元）

struct CompactControlButton: View {
    let command: CarCommand
    var isExecuting = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(WebTheme.card2)
                        .frame(width: 40, height: 40)
                    if isExecuting {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(iconColor)
                    } else {
                        Image(systemName: command.sfSymbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                }
                Text(command.displayName)
                    .font(.system(size: 9.5))
                    .foregroundStyle(WebTheme.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .accessibilityLabel("\(command.displayName)\(command.isDangerous ? "，高危操作" : "")")
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
    }

    private var iconColor: Color {
        command.isDangerous ? WebTheme.amber : WebTheme.blue
    }
}

/// 更多控车面板（保留入口，快捷排已含全部指令；此面板作为全量指令备用）
struct MoreControlsSheet: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                WebConsoleBackground()
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                        spacing: 18
                    ) {
                        ForEach(Array(CarCommand.extraCommands.enumerated()), id: \.element) { _, command in
                            CompactControlButton(
                                command: command,
                                isExecuting: viewModel.executingCommand == command
                            ) {
                                viewModel.execute(command)
                            }
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("更多控车")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(WebTheme.blue)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
