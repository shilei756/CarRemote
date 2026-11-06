import SwiftUI
import CarCore

/// ID.CONTROL 风格三屏外壳：概览 / 空调 / 车库，底部浮动白色胶囊导航。
/// 废弃原 5-tab 系统 TabView，改用自绘浮动胶囊（激活态红图标 + 灰色圆高亮）。
struct IDControlShell: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var tabRouter = TabRouter.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tabRouter.selectedTab {
                case .overview: DashboardView(appState: appState)
                case .climate: ClimateView()
                case .garage: GarageView()
                }
            }
            // 浮动白色胶囊导航
            HStack(spacing: 0) {
                idTabButton(.overview, title: "概览", icon: "square.grid.2x2.fill")
                idTabButton(.climate, title: "空调", icon: "fan.fill")
                idTabButton(.garage, title: "车库", icon: "folder.fill")
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.12), radius: 14, y: 5)
            )
            .padding(.horizontal, 26)
            .padding(.bottom, 18)
        }
        .ignoresSafeArea(edges: .bottom)
        .tint(WebTheme.blue)
    }

    private func idTabButton(_ tab: TabRouter.Tab, title: String, icon: String) -> some View {
        let active = tabRouter.selectedTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { tabRouter.select(tab) }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(active ? WebTheme.blue : WebTheme.muted)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(active ? WebTheme.blue : WebTheme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                active
                    ? Circle().fill(WebTheme.card2).frame(width: 52, height: 52)
                    : nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}

/// 控车主界面（ID.CONTROL「概览」屏）：点阵标题 + 居中 3D 车模 + 4 张分区卡
struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: DashboardViewModel

    init(appState: AppState) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(appState: appState))
    }

    @State private var showWallpaperSheet = false
    @State private var showNameEditor = false
    @State private var nameDraft = ""

    private var settings: AppSettings { SharedStore.loadSettings() }


    var body: some View {
        NavStack {
            ZStack {
                WebConsoleBackground()
                ScrollView {
                    VStack(spacing: 12) {
                        // 顶部栏：左设置圆钮 · 居中「ID. CONTROL」点阵标题 · 右远程/刷新圆钮
                        HStack(spacing: 12) {
                            // 左：设置圆钮
                            Button {
                                showWallpaperSheet = true
                            } label: {
                                Circle()
                                    .strokeBorder(WebTheme.border, lineWidth: 1)
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: "slider.horizontal.3")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(WebTheme.txt)
                                    )
                            }
                            .accessibilityLabel("设置")
                            Spacer()
                            // 中：点阵标题
                            Text("ID. CONTROL")
                                .font(Font.webLedFont(size: 20))
                                .foregroundStyle(WebTheme.txt)
                                .kerning(1)
                                .accessibilityLabel("ID. CONTROL")
                            Spacer()
                            // 右：远程信号（点击刷新车况）圆钮
                            Button {
                                Task { await appState.refreshStatus() }
                            } label: {
                                Circle()
                                    .strokeBorder(WebTheme.border, lineWidth: 1)
                                    .frame(width: 34, height: 34)
                                    .overlay(
                                        Image(systemName: "antenna.radiowaves.left.and.right")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(WebTheme.txt)
                                    )
                            }
                            .accessibilityLabel("刷新车况")
                            .disabled(appState.isRefreshing)
                        }
                        .padding(.top, 6)
                        // 车名（点阵 + 下拉箭头），点按改名
                        Button {
                            nameDraft = appState.customCarName
                            showNameEditor = true
                        } label: {
                            HStack(spacing: 4) {
                                Text(appState.carName.isEmpty ? "我的爱车" : appState.carName)
                                    .font(Font.webLedFont(size: 18))
                                    .foregroundStyle(WebTheme.txt)
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(WebTheme.faint)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("编辑车辆名称")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 2)
                        if let errorMessage = appState.errorMessage {
                            errorBanner(errorMessage)
                        }
                        if let status = appState.status {
                            carStage(status: status)
                            idOverviewCards(status: status)
                        } else {
                            loadingOrEmpty
                        }
                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 110)
                }
            .refreshable {
                await appState.refreshStatus()
            }
            .task {
                if viewModel.acMode == .new {
                    await viewModel.loadACRemainingDays()
                }
                // 实时状态轮询：每 30 秒自动刷新车况（开锁/闭锁后状态自动跟随，无需手动刷新）
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000)
                    if Task.isCancelled { break }
                    await appState.refreshStatus()
                }
            }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showNameEditor) {
                // 弹窗内 TextField 绑定在 iOS 上时序不稳，改用 sheet 表单保证写入可靠
                VStack(spacing: 16) {
                    Text("车辆名称")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(WebTheme.txt)
                        .padding(.top, 24)
                    TextField("给爱车起个名字", text: $nameDraft)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15))
                        .padding(.horizontal, 20)
                    Text("留空则显示官网车辆原名")
                        .font(.system(size: 11))
                        .foregroundStyle(WebTheme.faint)
                    HStack(spacing: 12) {
                        Button {
                            showNameEditor = false
                        } label: {
                            Text("取消")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(WebTheme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(WebTheme.card2)
                                .clipShape(Capsule())
                        }
                        Button {
                            appState.customCarName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            showNameEditor = false
                        } label: {
                            Text("保存")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(WebTheme.blue)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 20)
                    Spacer()
                }
                .compatHeight260Detent()
            }
            .toast(viewModel.toast)
            .compatOnChange(of: viewModel.toast) { newValue in
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
            .sheet(item: $viewModel.showEmbed) { _ in
                // 原生 UI（替代内嵌网页）；车况已独立成 tab，此处仅剩 360 全景
                PanoramaSheet()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $viewModel.showWhitelist) {
                WhitelistView()
                    .environmentObject(appState)
            }
            .sheet(isPresented: $viewModel.showLocationDetail) {
                locationDetailSheet
            }
            .sheet(isPresented: $viewModel.showACTempModal) {
                ACTempSheet(viewModel: viewModel)
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

    // MARK: - 浮动车模（网页版 car-stage：3D 车模/车图浮动 + 椭圆阴影 + 车况标签）

    private func carStage(status: CarStatus) -> some View {
        VStack(spacing: 0) {
            ZStack {
                // 测试版 ID.CONTROL 风格：车模后方柔和科技光晕（模拟展厅聚光）
                RadialGradient(
                    colors: [WebTheme.blue.opacity(0.16), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: 170
                )
                .frame(width: 300, height: 210)
                .blur(radius: 18)
                .accessibilityHidden(true)
                .allowsHitTesting(false)

                if settings.car3DEnabled && settings.carModelStyle.has3DModel {
                    // 官方 3D 车模（长安智慧云控展厅资产）：
                    // 左右滑动旋转 / 捏合缩放 / 长按部件开合 / 车窗车门随真实车况逐扇联动
                    CarVisual3DStage(
                        style: settings.carModelStyle,
                        doorsAndWindows: status.doorsAndWindows,
                        vehicleStarted: status.isVehicleStarted,
                        wheelsRolling: status.shouldRollWheels
                    )
                    .padding(.horizontal, 20)
                } else {
                    Image(settings.carModelStyle.sideImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 200)
                        .padding(.horizontal, 20)
                        .accessibilityLabel("\(settings.carModelStyle.displayName) 车辆图片")
                }
            }

            // 车下微光（ID.CONTROL：车底一圈淡辉光，替代网页版深色椭圆阴影）
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [WebTheme.blue.opacity(0.22), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 70
                    )
                )
                .frame(width: 190, height: 12)
                .padding(.top, -4)
                .opacity(0.9)

            // 车况状态徽章（网页版 carStateTags）：正常=绿色「车辆正常」，异常时跟随实时状态
            let badge = status.stateFlags.statusBadge
            HStack(spacing: 6) {
                Circle()
                    .fill(flagColor(key: badge.key))
                    .frame(width: 7, height: 7)
                Text(badge.text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(flagColor(key: badge.key))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(flagColor(key: badge.key).opacity(0.09))
            .clipShape(Capsule())
            .overlay(
                Capsule().strokeBorder(flagColor(key: badge.key).opacity(0.28), lineWidth: 1)
            )
            .padding(.top, 10)
            .accessibilityLabel("车辆状态：\(badge.text)")
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

    // MARK: - ID.CONTROL 分区大数字卡（测试版专属仪表风）

    /// 单张分区卡：细描边 + 图标标签 + 大号等宽数字 + 副标（对齐 ID.CONTROL 深色极简风）
    // MARK: - ID.CONTROL 概览分区卡（燃油 / 车辆状态 / 空调 / 停车位置）

    /// 统一白卡容器：白底 + 圆角 + 1px 描边 + 轻投影
    private func idCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WebTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: WebTheme.cardRadius, style: .continuous)
                    .strokeBorder(WebTheme.border, lineWidth: 1)
            )
    }

    /// 概览 4 张分区卡（纵向堆叠，对齐 ID. CONTROL 风格）
    private func idOverviewCards(status: CarStatus) -> some View {
        VStack(spacing: 12) {
            fuelCard(status)
            vehicleStatusCard(status)
            climateCard(status)
            parkingCard(status)
        }
    }

    /// 燃油卡：点阵大数字（油量% + 续航 km）+ 分段进度条 + 红演示提示
    private func fuelCard(_ status: CarStatus) -> some View {
        let pct = status.fuelLeftLiters ?? 0
        let ratio = min(1, max(0, pct / 100))
        return idCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("燃油").font(.system(size: 13, weight: .semibold)).foregroundStyle(WebTheme.txt)
                    Spacer()
                    Text("演示").font(.system(size: 11)).foregroundStyle(WebTheme.faint)
                }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "fuelpump.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WebTheme.blue)
                    Text(CarStatus.format(status.fuelLeftLiters))
                        .font(Font.webSegFont(size: 34)).foregroundStyle(WebTheme.txt)
                        .monospacedDigit()
                    Text("%").font(.system(size: 15, weight: .bold)).foregroundStyle(WebTheme.faint)
                    Spacer()
                    Text(CarStatus.format(status.remainingRangeKm))
                        .font(Font.webSegFont(size: 30)).foregroundStyle(WebTheme.txt)
                        .monospacedDigit()
                    Text("km").font(.system(size: 13, weight: .medium)).foregroundStyle(WebTheme.faint)
                }
                segmentedBar(ratio: ratio)
                HStack {
                    Text("预估续航").font(.system(size: 11)).foregroundStyle(WebTheme.faint)
                    Spacer()
                    HStack(spacing: 2) {
                        Text("燃油详情").font(.system(size: 11, weight: .medium)).foregroundStyle(WebTheme.blue)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(WebTheme.blue)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(WebTheme.blue)
                    Text("演示数据 · 绑定车辆后查看真实记录").font(.system(size: 11)).foregroundStyle(WebTheme.blue)
                }
            }
        }
    }

    /// 分段进度条：黑方块填充比例，余灰
    private func segmentedBar(ratio: CGFloat) -> some View {
        let total = 20
        let filled = Int((ratio * CGFloat(total)).rounded())
        return HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(i < filled ? WebTheme.txt : WebTheme.track)
                    .frame(height: 8)
            }
        }
    }

    /// 车辆状态卡：车身 / 门锁 / 燃油 三列
    private func vehicleStatusCard(_ status: CarStatus) -> some View {
        let dw = status.doorsAndWindows
        let bodyState = (dw.anyDoorUnlocked || dw.anyWindowOpen) ? "已开启·演示" : "已关闭·演示"
        let lockState = dw.anyDoorUnlocked ? "已开锁" : "已锁车"
        let fuelPct = CarStatus.format(status.fuelLeftLiters) + "%"
        return idCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("车辆状态").font(.system(size: 13, weight: .semibold)).foregroundStyle(WebTheme.txt)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(WebTheme.faint)
                }
                HStack(spacing: 0) {
                    statusColumn(icon: "car.side.rear", title: "车身", value: bodyState)
                    Divider().frame(height: 36).background(WebTheme.border)
                    statusColumn(icon: "lock.fill", title: "门锁", value: lockState)
                    Divider().frame(height: 36).background(WebTheme.border)
                    statusColumn(icon: "fuelpump.fill", title: "燃油", value: fuelPct)
                }
                Text("演示车辆状态 · 非实时").font(.system(size: 11)).foregroundStyle(WebTheme.faint)
            }
        }
    }

    private func statusColumn(icon: String, title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(WebTheme.muted)
            Text(title).font(.system(size: 11)).foregroundStyle(WebTheme.faint)
            Text(value).font(.system(size: 12, weight: .medium)).foregroundStyle(WebTheme.txt)
        }
        .frame(maxWidth: .infinity)
    }

    /// 空调卡：点阵温度 + 红圆「调整预览」钮（进入空调页）
    private func climateCard(_ status: CarStatus) -> some View {
        idCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("空调").font(.system(size: 13, weight: .semibold)).foregroundStyle(WebTheme.txt)
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(CarStatus.format(status.acTempC))
                            .font(Font.webSegFont(size: 30)).foregroundStyle(WebTheme.txt).monospacedDigit()
                        Text("℃").font(.system(size: 14, weight: .bold)).foregroundStyle(WebTheme.faint)
                    }
                }
                Spacer()
                Button {
                    TabRouter.shared.select(.climate)
                } label: {
                    ZStack {
                        Circle().fill(WebTheme.blue).frame(width: 44, height: 44)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    }
                }
                .accessibilityLabel("调整预览空调")
                .buttonStyle(.plain)
            }
        }
    }

    /// 停车位置卡
    private func parkingCard(_ status: CarStatus) -> some View {
        let hasLoc = status.location != nil
        return idCard {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.system(size: 18)).foregroundStyle(WebTheme.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text("停车位置").font(.system(size: 13, weight: .semibold)).foregroundStyle(WebTheme.txt)
                    Text(hasLoc ? "已上报位置" : "绑定车辆后查看位置")
                        .font(.system(size: 11)).foregroundStyle(WebTheme.faint)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(WebTheme.faint)
            }
        }
    }

    // MARK: - 车况卡（网页版 user-info-container：油量条 + 续航 + 里程 + 温度 + 电瓶条）

    private func vehicleInfoCard(status: CarStatus) -> some View {
        SectionCard(sakura: false) {
            HStack(alignment: .top, spacing: 12) {
                // 左列：油量/续航/里程/温度/电瓶（网页版 card 左列）
                VStack(spacing: 7) {
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
                        Text("/ \(CarStatus.format(SharedStore.loadSettings().tankCapacityL))L 油箱")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(WebTheme.faint)
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
                        fraction: (status.fuelLeftLiters ?? 0) / SharedStore.loadSettings().tankCapacityL,
                        fill: LinearGradient(colors: [WebTheme.amber, WebTheme.amber.opacity(0.7)], startPoint: .leading, endPoint: .trailing),
                        height: 4
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
                        height: 3
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
                    Image(settings.carModelStyle.topImageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 40, height: 97)
                        .opacity(0.9)
                        .accessibilityLabel("\(settings.carModelStyle.displayName) 俯视图")
                }
                .frame(width: 88, height: 104)
                .overlay(alignment: .topLeading) {
                    tireBadge(status.tirePressures[0], label: "左前").offset(x: -7)
                }
                .overlay(alignment: .topTrailing) {
                    tireBadge(status.tirePressures[1], label: "右前").offset(x: 7)
                }
                .overlay(alignment: .bottomLeading) {
                    tireBadge(status.tirePressures[2], label: "左后").offset(x: -7)
                }
                .overlay(alignment: .bottomTrailing) {
                    tireBadge(status.tirePressures[3], label: "右后").offset(x: 7)
                }
            }
        }
    }

    private func fuelPercent(_ liters: Double?) -> Int {
        guard let liters else { return 0 }
        let capacity = SharedStore.loadSettings().tankCapacityL
        guard capacity > 0 else { return 0 }
        return Int(min(max((liters / capacity) * 100, 0), 100).rounded())
    }

    /// 电瓶电压告警：低于 11.8V 或高于 14.8V 视为异常（燃油车常见区间）
    private func voltageColor(_ voltage: Double?) -> Color {
        guard let voltage else { return WebTheme.green }
        if voltage < 11.8 || voltage > 14.8 { return WebTheme.red }
        return WebTheme.green
    }

    // MARK: - 快捷控车（网页版 quickCard：闪灯/开锁/闭锁/鸣笛，中间两个为描边大钮）

    private var quickControlsCard: some View {
        let commands = settings.visibleQuickCommands
        return Group {
            if commands.isEmpty {
                EmptyView()
            } else {
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(commands.enumerated()), id: \.element) { _, command in
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
                .controlBarStyle()
            }
        }
    }

    // MARK: - 更多指令（网页版 ctrlCard / moreGrid：5 列网格）

    private var moreControlsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题行：更多控车 + 空调控制（新版/官方版切换）与标题同行对齐
            // 开通状态提示放在「空调」左侧（横排，不挤右侧）
            HStack(spacing: 8) {
                Text("更多控车")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
                Spacer(minLength: 8)
                if viewModel.acMode == .new {
                    // 开通剩余日期（已开通才显示），位于「空调」左侧
                    if let days = viewModel.acRemainingDays {
                        Text("剩余 \(days) 天")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(days <= 1 ? WebTheme.red : WebTheme.green)
                    } else {
                        Text("需开通")
                            .font(.system(size: 9))
                            .foregroundStyle(WebTheme.amber)
                    }
                }
                Text("空调")
                    .font(.system(size: 10))
                    .foregroundStyle(WebTheme.faint)
                acModeSlider
            }
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 5),
                spacing: 14
            ) {
                ForEach(Array(settings.visibleMoreCommands.enumerated()), id: \.element) { _, command in
                    CompactControlButton(
                        command: command,
                        isExecuting: viewModel.executingCommand == command
                    ) {
                        viewModel.execute(command)
                    }
                }
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: 空调模式胶囊滑块（与车模 3D/2D 切换同款交互）

    private var acModeSlider: some View {
        HStack(spacing: 0) {
            acModeSegment(.new, title: "新版")
            acModeSegment(.official, title: "官方")
        }
        .padding(3)
        .background(Color(.secondarySystemBackground).opacity(0.9))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(WebTheme.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("空调控制模式")
        .accessibilityHint("可在新版开放平台链路与官方直连链路之间切换")
    }

    private func acModeSegment(_ mode: ACMode, title: String) -> some View {
        let selected = viewModel.acMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { viewModel.setACMode(mode) }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.white : WebTheme.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(selected ? WebTheme.blue : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(mode == .new ? "新版（开放平台）" : "官方版（直连）")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - 定位入口（点击才查询 + 详情弹窗，对齐网页版 locCard 效果）

    private var locationEntryCard: some View {
        Button {
            viewModel.queryLocation()
        } label: {
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
                        Text("点击查询当前位置")
                            .font(.system(size: 11))
                            .foregroundStyle(WebTheme.muted)
                    }
                    Spacer()
                    if viewModel.isLoadingLocation {
                        ProgressView()
                            .tint(WebTheme.muted)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WebTheme.faint)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("查询车辆位置")
    }

    /// 位置详情弹窗（网页版 locModal：地址/城市/定位时间/经纬度/车速 + 导航）
    private var locationDetailSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("车辆位置详情")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
                Spacer()
                Button {
                    viewModel.showLocationDetail = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(WebTheme.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭")
            }
            if viewModel.isLoadingLocation && viewModel.locationInfo == nil {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(WebTheme.purple)
                    Text("正在定位车辆…")
                        .font(.system(size: 12))
                        .foregroundStyle(WebTheme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else if let info = viewModel.locationInfo {
                VStack(spacing: 0) {
                    locationDetailRow("地址", icon: "mappin.and.ellipse", value: info.address.isEmpty ? "暂无地址" : info.address)
                    Divider().overlay(WebTheme.border)
                    if !info.city.isEmpty {
                        locationDetailRow("城市", icon: "buildings.2", value: info.city)
                        Divider().overlay(WebTheme.border)
                    }
                    if !info.gpsTime.isEmpty {
                        locationDetailRow("定位时间", icon: "clock", value: info.gpsTime)
                        Divider().overlay(WebTheme.border)
                    }
                    locationDetailRow("经纬度", icon: "scope", value: String(format: "%.6f, %.6f", info.latitude, info.longitude))
                    if let speed = info.speed {
                        Divider().overlay(WebTheme.border)
                        locationDetailRow("车速", icon: "speedometer", value: String(format: "%.0f km/h", speed))
                    }
                }
                .background(WebTheme.card2)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack(spacing: 10) {
                    Button {
                        viewModel.loadLocation()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                            Text("刷新位置")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(WebTheme.txt)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(WebTheme.card2)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Button {
                        viewModel.navigateToCar()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond")
                                .font(.system(size: 12, weight: .semibold))
                            Text("导航到车")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(WebTheme.navGradient)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "location.slash")
                        .font(.system(size: 26))
                        .foregroundStyle(WebTheme.faint)
                    Text("暂无位置信息，点「刷新位置」重试")
                        .font(.system(size: 12))
                        .foregroundStyle(WebTheme.muted)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                Button {
                    viewModel.loadLocation()
                } label: {
                    Text("刷新位置")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WebTheme.txt)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(WebTheme.card2)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .compatMediumDetent()
        .compatDragIndicator()
    }

    private func locationDetailRow(_ title: String, icon: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.purple)
                .frame(width: 20)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(WebTheme.muted)
            Spacer()
            Text(value)
                .font(.system(size: 12.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(WebTheme.txt)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }


    // MARK: - 更多功能（网页版 moreGrid：磁贴顺序支持自定义）

    private var moreToolsCard: some View {
        let tools = settings.visibleMoreTools
        return Group {
            if tools.isEmpty {
                EmptyView()
            } else {
                SectionCard(title: "更多功能", sakura: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                        spacing: 14
                    ) {
                        ForEach(tools, id: \.self) { tool in
                            // 白名单管理仅管理员可见
                            if tool != .whitelist || appState.isAdminUser {
                                moreToolTile(name: tool.displayName,
                                             symbol: tool.sfSymbol,
                                             color: Color(hex: UInt(tool.colorHex))) {
                                    handleTool(tool)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .sheet(isPresented: $showWallpaperSheet) {
            WallpaperSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $viewModel.showLayoutEditor) {
            LayoutEditorSheet(viewModel: viewModel)
        }
    }

    /// 磁贴点击分发
    private func handleTool(_ tool: MoreTool) {
        switch tool {
        case .refreshStatus:
            Task { await appState.refreshStatus() }
        case .history:
            viewModel.showHistoryActions = true
        case .messages:
            viewModel.showMessages = true
        case .trips:
            viewModel.showTrips = true
        case .acActivate:
            viewModel.showACQR = true
        case .vehicleStatus:
            // 车况已并入底部「车库」页列表，跳转至车库
            TabRouter.shared.select(.garage)
        case .panorama:
            viewModel.showEmbed = .panorama
        case .maintenance:
            TabRouter.shared.select(.garage)
        case .wallpaper:
            showWallpaperSheet = true
        case .customize:
            viewModel.showLayoutEditor = true
        case .whitelist:
            viewModel.showWhitelist = true
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
        NavStack {
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
            .inlineTitle("更多控车")
            .toolbar {
                ToolbarItem(placement: CompatToolbarPlacement.topTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(WebTheme.blue)
                }
            }
        }
        .compatMediumLargeDetents()
    }
}

// MARK: - 开空调调温弹窗（网页版 acTempModal：16~32°C，默认温度 = 上次使用 > 车机当前设定 > 24）

struct ACTempSheet: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var temp = 24
    @State private var initialized = false

    var body: some View {
        ZStack {
            WebConsoleBackground()
            VStack(spacing: 16) {
                Text("开启空调")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
                    .padding(.top, 20)

                // 车机当前设定温度（网页版 acTempCarVal）
                Text("车机当前设定温度 \(CarStatus.format(appState.status?.acTempC))°C，可在下方选择目标温度一并下发")
                    .font(.system(size: 11))
                    .foregroundStyle(WebTheme.faint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // − / 温度 / ＋（网页版 acTempAdjust：16~32 钳制）
                HStack(spacing: 24) {
                    Button {
                        temp = max(16, temp - 1)
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(WebTheme.txt)
                            .frame(width: 48, height: 48)
                            .background(WebTheme.card2)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(WebTheme.border, lineWidth: 1))
                    }
                    .disabled(temp <= 16)
                    .accessibilityLabel("降低目标温度")

                    Text("\(temp)°C")
                        .font(.system(size: 34, weight: .heavy))
                        .monospacedDigit()
                        .foregroundStyle(WebTheme.txt)
                        .frame(minWidth: 120)
                        .accessibilityLabel("目标温度 \(temp) 摄氏度")

                    Button {
                        temp = min(32, temp + 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(WebTheme.txt)
                            .frame(width: 48, height: 48)
                            .background(WebTheme.card2)
                            .clipShape(Circle())
                            .overlay(Circle().strokeBorder(WebTheme.border, lineWidth: 1))
                    }
                    .disabled(temp >= 32)
                    .accessibilityLabel("升高目标温度")
                }

                Text("16 ~ 32°C ｜ 部分车型支持预设温度，不支持时空调将按车机设定开启")
                    .font(.system(size: 10))
                    .foregroundStyle(WebTheme.faint)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()

                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("取消")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(WebTheme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .background(WebTheme.card2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消，不执行")

                    Button {
                        confirm()
                    } label: {
                        HStack(spacing: 6) {
                            if viewModel.executingCommand == .openAir {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text("开启空调")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(WebTheme.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.executingCommand != nil)
                    .accessibilityLabel("确认以 \(temp) 摄氏度开启空调")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .onAppear {
            guard !initialized else { return }
            temp = viewModel.defaultACTemp(currentCarTemp: appState.status?.acTempC)
            initialized = true
        }
        .compatOnChange(of: viewModel.executingCommand) { newValue in
            // 指令执行完毕（成功或失败）自动关闭，结果由 toast 提示
            if newValue == nil, initialized {
                dismiss()
            }
        }
    }

    /// 确认：防误触开启时先弹确认框（confirmPending 会带上温度），否则直接下发
    private func confirm() {
        viewModel.confirmACTemp(temp)
        if viewModel.pendingConfirm == nil {
            dismiss()
        }
    }
}
