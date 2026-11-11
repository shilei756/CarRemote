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
                Text("正在验证网站授权").font(.system(size: 10)).foregroundStyle(Mono.nightDim)
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
                .padding(.bottom, 92 + (control.receipt != nil ? 40 : 0))
                .animation(.easeInOut(duration: 0.22), value: control.receipt != nil)

                VStack(spacing: 0) {
                    if let receipt = control.receipt {
                        receiptView(receipt)
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
        .onAppear {
            Task { await appState.refreshStatus() }
        }
        .onChange(of: selectedID) { newValue in
            CakocheModels.selectedID = newValue
            cockpit = false
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

    /// 1.1.0：中文化视角切换。点阵不支持中文，改用宽字距黑体保持克制观感。
    private func viewButton(_ title: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(on ? Mono.paperInk : Mono.paperHair)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    DotMatrixText(text: "KM", size: 11, color: Mono.paperDim)
                    Text("剩余续航").font(.system(size: 10)).foregroundStyle(Mono.paperDim)
                }
                .padding(.bottom, 6)
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text("总里程")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(1.5)
                        .foregroundStyle(Mono.paperDim)
                    Text(odoText)
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Mono.paperInk)
                }
                .padding(.bottom, 6)
            }
            BlockBar(progress: fuelProgress, blocks: 30,
                     color: Mono.paperInk, dim: Mono.paperHair)
                .frame(height: 5)
            HStack {
                Text("油量")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(2)
                    .foregroundStyle(Mono.paperDim)
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
                        Text(items[i].key)
                            .font(.system(size: 9, weight: .medium))
                            .tracking(1.5)
                            .foregroundStyle(Mono.paperDim)
                        Text(items[i].value)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(items[i].alarm ? Mono.red : Mono.paperInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
        }
    }

    // MARK: 底部回执 + 控车把手

    private func receiptView(_ r: CakocheReceipt) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: r.ok ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(r.ok ? Mono.paperInk : Mono.red)
                .padding(.top, 2)
            Text("\(r.command) · \(r.detail)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Mono.paperInk)
                // 1.1.0：失败原因可能较长，允许换行两行并自动缩小，不再被截断
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
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
                    Text("控车")
                        .font(.system(size: 15, weight: .semibold))
                        .tracking(4)
                    Spacer()
                    Text("点按或上滑").font(.system(size: 10)).foregroundStyle(Mono.paperDim)
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

    private var fuelProgress: Double {
        guard let liters = status?.fuelLeftLiters else { return 0 }
        return min(1, max(0, liters / 55.0))
    }
    private var fuelText: String {
        guard let liters = status?.fuelLeftLiters else { return "-- L" }
        return String(format: "%.1f L", liters)
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

    private let commands: [CarCommand] = [
        .unlockDoor, .lockDoor, .oneKeyLock, .closeWindow,
        .openWindow, .openEngine, .closeEngine, .closeDormer,
        .flashLight, .whistle, .remoteSearchCar
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Mono.night.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("控车")
                                .font(.system(size: 20, weight: .semibold))
                                .tracking(6)
                                .foregroundStyle(Mono.nightInk)
                            Text("指令直接下发至车辆")
                                .font(.system(size: 10))
                                .foregroundStyle(Mono.nightDim)
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

                    Hairline(color: Mono.nightHair).padding(.top, 20)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 2),
                              spacing: 1) {
                        ForEach(commands, id: \.self) { command in
                            Button {
                                Task { await control.run(command) }
                            } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Image(systemName: command.sfSymbol)
                                            .font(.system(size: 20, weight: .light))
                                            .foregroundStyle(command.isDangerous ? Mono.red : Mono.nightInk)
                                        Spacer()
                                        if control.executing == command {
                                            ProgressView().tint(Mono.nightInk).scaleEffect(0.7)
                                        }
                                    }
                                    // 1.1.0：去掉点阵英文指令名（过长会被裁切），只留中文名
                                    Text(command.displayName)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(Mono.nightInk)
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

                    if let r = control.receipt {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(r.ok ? "执行成功" : "执行失败")
                                .font(.system(size: 12, weight: .semibold))
                                .tracking(3)
                                .foregroundStyle(r.ok ? Mono.nightInk : Mono.red)
                            Text("\(r.command) · \(r.detail) · \(r.timeText)")
                                .font(.system(size: 11))
                                .foregroundStyle(Mono.nightDim)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 22)
                    }

                    Button {
                        Task { await appState.refreshStatus() }
                    } label: {
                        HStack {
                            Text("刷新车况")
                                .font(.system(size: 12, weight: .medium))
                                .tracking(3)
                            Spacer()
                            Image(systemName: "arrow.clockwise").font(.system(size: 12))
                        }
                        .foregroundStyle(Mono.nightDim)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 18)
                    }
                    .buttonStyle(.plain)

                    Text("首页车模可拖拽旋转，切换 INT 进入真实座舱；所有按钮是真指令，不是演示。")
                        .font(.system(size: 10))
                        .foregroundStyle(Mono.nightDim)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 22)
                        .padding(.bottom, 34)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
