import SwiftUI
import CarCore

/// CAKOCHE 根视图：加载 → 白名单校验 → 主界面 / 登录。
/// 与正式版 RootView 完全分离，不复用任何 tab / 公告 / 主题逻辑。
struct CakocheRootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            switch appState.phase {
            case .loading:
                CakocheSplash()
            case .ready:
                CakocheHome()
            case .loggedOut, .needsCard:
                CakocheLoginView()
            }
        }
        .animation(.easeInOut(duration: 0.22), value: appState.phase)
    }
}

struct CakocheSplash: View {
    var body: some View {
        ZStack {
            Mono.night.ignoresSafeArea()
            VStack(spacing: 18) {
                DotMatrixText(text: "CAKOCHE", size: 26, color: Mono.nightInk)
                ProgressView().tint(Mono.nightInk)
                DotCnText(text: "正在验证网站授权", size: 9, color: Mono.nightDim)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - 主界面：三屏左右滑 + 底部控车抽屉

struct CakocheHome: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var control = CakocheControl()
    @State private var page = 0
    @State private var showControl = false
    @State private var cockpit = false
    @State private var selectedID = CakocheModels.selectedID
    /// 油量点阵配色：空 = 多色随机（默认）；非空 = 用户指定单色（hex）
    @AppStorage("cakoche.fuelDot.hex") private var fuelDotHex = ""
    @State private var showFuelColor = false
    /// 1.2.6：快捷指令「打开 App 页面」的落地页（首页 / 空调 / 我的）
    @Environment(\.scenePhase) private var scenePhase

    private var model: CakocheModel {
        CakocheModels.all.first { $0.id == selectedID } ?? CakocheModels.all[0]
    }
    private var status: CarStatus? { appState.status }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                Mono.paper.ignoresSafeArea()

                TabView(selection: $page) {
                    carPage(geo: geo).tag(0)
                    CakocheClimatePage(control: control).tag(1)
                    CakocheSettingsPage(control: control, selectedID: $selectedID).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                // 1.1.0：回执出现时动态抬高页面底部，不再压住状态格最后一行；
                // 回执消失时同样动态回落。高度含上下内边距（9 + 9 + 两行余量）。
                .padding(.bottom, 92 + (control.receipt != nil ? 48 : 0))
                .animation(.easeInOut(duration: 0.22), value: control.receipt != nil)

                VStack(spacing: 0) {
                    if let receipt = control.receipt {
                        receiptView(receipt, availableWidth: geo.size.width - 130)
                    }
                    Hairline(color: Mono.paperHair)
                    bottomBar
                }
                .background(Mono.paper)
            }
        }
        .sheet(isPresented: $showControl) {
            CakocheControlSheet(control: control)
        }
        .sheet(isPresented: $showFuelColor) {
            FuelColorPickerSheet(hex: $fuelDotHex)
        }
        .onAppear {
            applyPendingPage()
            Task { await appState.refreshStatus() }
        }
        // 快捷指令在 App 已在前台时也能切页：回到 active 时再取一次
        .onChange(of: scenePhase) { phase in
            if phase == .active { applyPendingPage() }
        }
        .onChange(of: selectedID) { newValue in
            CakocheModels.selectedID = newValue
            cockpit = false
        }
    }

    /// 消费快捷指令写下的「待跳转页面」标记（读完即清，不会重复跳）
    /// 取值与 `CakochePageOption` 的 rawValue 一致：home / climate / mine
    private func applyPendingPage() {
        guard let raw = CakochePendingPage.consume() else { return }
        switch raw {
        case "climate": page = 1
        case "mine": page = 2
        default: page = 0
        }
    }

    // MARK: 上滑手势（1.1.0）

    /// 车页任意位置竖直上滑即唤出控车抽屉，不再必须点「上滑控车」按钮。
    /// 与 TabView 横向翻页、车模旋转手势并存：只响应「纵向主导 + 上滑」的拖动，
    /// 横向（翻页）与斜向（旋转车模）一律不触发。
    private var swipeUpToControl: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = abs(value.translation.width)
                let dy = value.translation.height
                guard dy < -40, dy < -dx * 1.4 else { return }
                showControl = true
            }
    }

    // MARK: 车 · 首页

    private func carPage(geo: GeometryProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            stage(geo: geo)
            hero
            Spacer(minLength: 8)
            statusGrid
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(swipeUpToControl)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                DotMatrixText(text: "CAKOCHE", size: 15, color: Mono.paperInk)
                Text(model.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Mono.paperDim)
            }
            Spacer()
            HStack(spacing: 16) {
                viewButton("车外", !cockpit) { cockpit = false }
                viewButton("车内", cockpit) { cockpit = true }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
    }

    /// 1.2.0：视角切换点阵化
    private func viewButton(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                DotCnText(text: title, size: 10,
                          color: on ? Mono.paperInk : Mono.paperHair)
                Rectangle()
                    .fill(on ? Mono.red : Color.clear)
                    .frame(width: 18, height: 2)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "车外" ? "车外视角" : "车内座舱视角")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// 3D 真车模铺满：指定 12 款之一，隐藏原胶囊控件，切 INT 进 c211 完整座舱。
    /// 换车型 / 换内外都换 .id 强制重建舞台，避免同一 ARView 中途换 GLB 卡死（1.8.0 教训）。
    private func stage(geo: GeometryProxy) -> some View {
        let height = max(210, geo.size.height * 0.42)
        return CarVisual3DStage(
            style: .yidongWhite,
            doorsAndWindows: status?.doorsAndWindows ?? CarStatus.DoorsAndWindows(),
            vehicleStarted: status?.isVehicleStarted ?? false,
            wheelsRolling: status?.shouldRollWheels ?? false,
            modelOverride: cockpit ? CakocheModels.cockpitGLB(for: model) : model.glb,
            minimalChrome: true,
            stageHeight: height,
            cockpitOverride: cockpit
        )
        .id("ck-stage-\(model.id)-\(cockpit ? "int" : "ext")")
        .frame(height: height)
        .clipped()
    }

    private var hero: some View {
        let rangeText: String = {
            guard let value = status?.remainingRangeKm else { return "---" }
            return String(format: "%.0f", value)
        }()
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .bottom, spacing: 12) {
                DotMatrixText(text: rangeText, size: 56, color: Mono.paperInk)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 3) {
                    DotMatrixText(text: "KM", size: 11, color: Mono.paperDim)
                    DotCnText(text: "剩余续航", size: 9, color: Mono.paperDim)
                }
                .padding(.bottom, 6)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    DotCnText(text: "总里程", size: 8, color: Mono.paperDim)
                    Text(odoText)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Mono.paperInk)
                }
                .padding(.bottom, 6)
            }
            // 1.2.5：跃动油量条（默认多色随机，点按进入配色面板）
            FuelDotBar(progress: fuelProgress, rows: 7,
                       color: fuelDotHex.isEmpty ? nil : Color(hex: fuelDotHex),
                       dim: Mono.paperHair)
                .frame(height: 34)
                .contentShape(Rectangle())
                .onTapGesture { showFuelColor = true }
                .accessibilityHint("点按自定义油量点阵颜色")
            HStack(alignment: .center) {
                DotCnText(text: "油量", size: 8, color: Mono.paperDim)
                Spacer()
                Button { showFuelColor = true } label: {
                    HStack(spacing: 4) {
                        DotCnText(text: "点按换色", size: 8, color: Mono.paperDim)
                        Image(systemName: "paintpalette")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Mono.paperDim)
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(fuelText)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(Mono.paperDim)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 4)
    }

    private var statusGrid: some View {
        let flags = status?.stateFlags
        // 1.1.0：键与值全部中文化（点阵仅保留品牌字与数值），值短词保证三列不挤压
        let items: [(key: String, value: String, alarm: Bool)] = [
            ("车门",   flags?.doorUnlocked == true ? "已解锁" : "已上锁", flags?.doorUnlocked == true),
            ("车窗",   flags?.windowOpen == true ? "开启" : "关闭",       flags?.windowOpen == true),
            ("发动机", flags?.engineRunning == true ? "运行中" : "熄火",  false),
            ("胎压",   lowTire ? "偏低" : "正常",                          lowTire),
            ("电压",   voltText,                                           false),
            ("车内温度", tempText,                                         false)
        ]
        return VStack(spacing: 0) {
            Hairline(color: Mono.paperHair)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                      spacing: 16) {
                ForEach(items.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        DotCnText(text: items[i].key, size: 8, color: Mono.paperDim)
                        DotCnText(text: items[i].value, size: 11,
                                  color: items[i].alarm ? Mono.red : Mono.paperInk)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
    }

    // MARK: 底部回执 + 控车把手

    private func receiptView(_ r: CakocheReceipt, availableWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: r.ok ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(r.ok ? Mono.paperInk : Mono.red)
                .padding(.top, 3)
            DotCnText(text: "\(r.command) · \(r.detail)", size: 9, color: Mono.paperInk,
                      wrapWidth: max(120, availableWidth), wrapAlignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(r.timeText)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(Mono.paperDim)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 9)
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Button {
                showControl = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.up").font(.system(size: 11, weight: .bold))
                    DotCnText(text: "控 车", size: 12, color: Mono.paperInk)
                    Spacer()
                    DotCnText(text: "点按或上滑", size: 8, color: Mono.paperDim)
                }
                .foregroundStyle(Mono.paperInk)
                .padding(.horizontal, 22)
                .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开控车面板")
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Mono.paperInk : Mono.paperHair)
                        .frame(width: i == page ? 16 : 5, height: 3)
                }
            }
            .padding(.bottom, 10)
        }
    }

    // MARK: 派生数值

    /// 1.2.2：油量按所选车型的油箱容积换算（网页版 CAR_MODELS.tank 机制），
    /// 不再写死 55L；切车型后进度条与文案一起联动。
    private var fuelProgress: Double {
        guard let liters = status?.fuelLeftLiters else { return 0 }
        return min(1, max(0, liters / model.tankL))
    }
    private var fuelText: String {
        guard let liters = status?.fuelLeftLiters else {
            return String(format: "-- / %.0f L", model.tankL)
        }
        return String(format: "%.1f / %.0f L", liters, model.tankL)
    }
    private var odoText: String {
        guard let odo = status?.totalOdometerKm else { return "--" }
        return String(format: "%.0f km", odo)
    }
    private var voltText: String {
        guard let volt = status?.batteryVoltage else { return "--" }
        return String(format: "%.1f V", volt)
    }
    private var tempText: String {
        guard let temp = status?.vehicleTempC else { return "--" }
        return String(format: "%.0f℃", temp)
    }
    private var lowTire: Bool {
        status?.tirePressures.contains { $0.isLow } ?? false
    }
}

// MARK: - 控车抽屉（反相黑底）

struct CakocheControlSheet: View {
    @ObservedObject var control: CakocheControl
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    /// 1.2.0：所有控车指令都需二次确认
    @State private var confirmTarget: CarCommand?

    private let commands: [CarCommand] = [
        .unlockDoor, .lockDoor, .oneKeyLock, .closeWindow,
        .openWindow, .openEngine, .closeEngine, .closeDormer,
        .flashLight, .whistle, .remoteSearchCar
    ]

    /// 车况状态条：一切正常白色，有异常红色逐项列出
    private var abnormalItems: [String] {
        let flags = appState.status?.stateFlags
        var items: [String] = []
        if flags?.doorUnlocked == true { items.append("车门已解锁") }
        if flags?.windowOpen == true { items.append("车窗未关") }
        if flags?.sunroofOpen == true { items.append("天窗未关") }
        if flags?.engineRunning == true { items.append("发动机运行中") }
        if appState.status?.tirePressures.contains(where: { $0.isLow }) == true { items.append("胎压偏低") }
        return items
    }

    var body: some View {
        ZStack(alignment: .top) {
            Mono.night.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            DotCnText(text: "控 车", size: 16, color: Mono.nightInk)
                            DotCnText(text: "指令直接下发至车辆 · 点击后二次确认", size: 8, color: Mono.nightDim)
                        }
                        Spacer()
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Mono.nightDim)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().stroke(Mono.nightHair, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭控车面板")
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 26)

                    // 1.2.0：车况状态条 —— 一切正常白色，有异常红色逐项列出
                    Group {
                        if abnormalItems.isEmpty {
                            DotCnText(text: "一切正常", size: 10, color: Mono.nightInk)
                        } else {
                            DotCnText(text: abnormalItems.joined(separator: " · "), size: 10,
                                      color: Mono.red, wrapAlignment: .leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 22)
                    .padding(.top, 14)

                    Hairline(color: Mono.nightHair).padding(.top, 16)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 2),
                              spacing: 1) {
                        ForEach(commands, id: \.self) { command in
                            Button {
                                confirmTarget = command
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        // 1.2.0：图标统一白色，异常信息只由状态条用红色表达
                                        Image(systemName: command.sfSymbol)
                                            .font(.system(size: 20, weight: .light))
                                            .foregroundStyle(Mono.nightInk)
                                        Spacer()
                                        if control.executing == command {
                                            ProgressView().tint(Mono.nightInk).scaleEffect(0.7)
                                        }
                                    }
                                    DotCnText(text: command.displayName, size: 11, color: Mono.nightInk)
                                }
                                .padding(16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Mono.night)
                                .overlay(Rectangle().stroke(Mono.nightHair, lineWidth: 0.5))
                            }
                            .buttonStyle(.plain)
                            .disabled(control.executing != nil)
                            .accessibilityLabel(command.displayName)
                        }
                    }
                    .padding(.top, 1)

                    if let r = control.receipt {
                        VStack(alignment: .leading, spacing: 7) {
                            DotCnText(text: r.ok ? "执行成功" : "执行失败", size: 10,
                                      color: r.ok ? Mono.nightInk : Mono.red)
                            DotCnText(text: "\(r.command) · \(r.detail) · \(r.timeText)", size: 8,
                                      color: Mono.nightDim, wrapAlignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.top, 22)
                    }

                    Button {
                        Task { await appState.refreshStatus() }
                    } label: {
                        HStack {
                            DotCnText(text: "刷 新 车 况", size: 10, color: Mono.nightDim)
                            Spacer()
                            Image(systemName: "arrow.clockwise").font(.system(size: 12))
                        }
                        .foregroundStyle(Mono.nightDim)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)

                    DotCnText(text: "首页车模可拖拽旋转，切换「车内」进入真实座舱；所有按钮为真实指令，点击后需二次确认下发。",
                              size: 8, color: Mono.nightDim, wrapAlignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 34)
                }
            }
        }
        // 1.2.0：所有控车功能二次确认
        .alert("确认执行", isPresented: Binding(
            get: { confirmTarget != nil },
            set: { if !$0 { confirmTarget = nil } }
        )) {
            Button("取消", role: .cancel) { confirmTarget = nil }
            Button("确认下发", role: .destructive) {
                if let command = confirmTarget {
                    Task { await control.run(command) }
                }
                confirmTarget = nil
            }
        } message: {
            Text("确认要执行「\(confirmTarget?.displayName ?? "")」吗？该指令将直接下发至车辆。")
        }
        .preferredColorScheme(.dark)
    }
}
