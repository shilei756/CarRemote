import SwiftUI
import RealityKit
import CarCore

// =============================================================
// 3D 车模舞台（智慧云控风格交互）
//
// 交互设计（对齐长安智慧云控车模页）：
//   - 左右滑动车模 → 360° 旋转（轨道方位角；纵向滑动透传给仪表盘滚动，不冲突）
//   - 捏合 → 缩放视距；双击 → 重置视角
//   - 长按车模上的部件（车门/尾门/天窗）→ 直接开合（智慧云控「触控点控车」）
//   - 底部横向滚动控制条：四门 / 尾门 / 天窗 / 车窗 / 车灯 / 车轮 / 重置视角
//   - 车模随真实车况自动同步：闭锁态把手收回、开锁态把手弹出 + 门灯亮、
//     车窗/天窗开合跟随车况（状态没变化时不动车模，避免覆盖本地预览）
//
// 注意：车门/尾门/天窗芯片为「本机预览」——长安远程指令中没有单独的开闭
// 某扇门/尾门的接口（只有全车解锁/闭锁与全车车窗），真实控制请用下方
// 「快捷控车 / 更多控车」按钮；车况刷新后车模会自动回归真实状态。
// =============================================================

// MARK: - 车模状态（芯片与触控点共用的单一数据源）

final class Car3DModelState: ObservableObject {
    /// 开启中的部件（车门 / 尾门 / 天窗）
    @Published private(set) var openParts: Set<CarPart> = []
    /// 车窗是否降下
    @Published private(set) var windowsOpen = false
    /// 车灯是否点亮（前灯 + 尾灯）
    @Published private(set) var lightsOn = false
    /// 车轮是否转动
    @Published private(set) var wheelsSpinning = false
    /// 模型可用的部件（加载后由场景节点决定）
    @Published private(set) var availableParts: Set<CarPart> = []
    /// 是否有可独立升降的车窗
    @Published private(set) var hasWindows = false
    /// 是否有可点亮的灯光件（外购单 mesh 模没有）
    @Published private(set) var hasLights = false
    /// 是否有可转动的车轮件
    @Published private(set) var hasWheels = false
    /// 场景是否已挂载（glb 解析 + 索引完成）
    @Published private(set) var isLoaded = false
    /// 加载是否失败（失败时 UI 自动回退 2D 车图）
    @Published private(set) var loadFailed = false

    private weak var sceneView: Car3DView?

    /// 最近一次同步的真实车况（值没变就不动车模，避免覆盖用户的本地预览）
    private var lastSyncedStatus: (unlocked: Bool, window: Bool, sunroof: Bool)?

    /// 加载代次：每次创建新视图 +1，旧加载完成时按代次丢弃。
    /// 防止 SwiftUI 重建 representable 时，旧 Task 把已废弃的视图挂成当前场景。
    private var loadGeneration = 0

    private static let doorParts: [CarPart] = [.doorFrontLeft, .doorFrontRight, .doorRearLeft, .doorRearRight]

    // MARK: 挂载

    func attach(_ view: Car3DView) {
        sceneView = view
        availableParts = view.availableParts
        hasWindows = view.hasWindows
        hasLights = view.hasLights
        hasWheels = view.hasWheels
        // 视图重建后把当前开合态应用回去
        for part in openParts { view.setPart(part, open: true, duration: 0.001) }
        if windowsOpen {
            for part in Self.doorParts { view.setWindow(part, open: true, duration: 0.001) }
        }
        view.setLights(headlight: lightsOn, taillight: lightsOn)
        if wheelsSpinning { view.startWheels(rpm: 5) } else { view.stopWheels() }
        // 重放加载完成前到达的真实车况（真实状态优先于本地预览）
        if let last = lastSyncedStatus {
            view.setUnlocked(last.unlocked)
            setWindows(last.window)
            setPart(.sunroof, open: last.sunroof)
        }
    }

    func ensureAttached(_ view: Car3DView) {
        if sceneView !== view { attach(view) }
    }

    func detach() {
        sceneView = nil
    }

    // MARK: 加载（后台解析 → 主线程挂载）

    /// 开始一次加载，返回代次（调用方在完成回调里比对）
    func beginLoad() -> Int {
        loadGeneration += 1
        isLoaded = false
        loadFailed = false
        return loadGeneration
    }

    /// 后台加载完成（主线程调用）：代次不匹配说明视图已重建，直接丢弃
    func completeLoad(generation: Int, view: Car3DView, model: RKCarModel?) {
        guard generation == loadGeneration else { return }
        if let model, view.attach(model) {
            attach(view)
            isLoaded = true
        } else {
            loadFailed = true
        }
    }

    // MARK: 部件控制

    func toggle(_ part: CarPart) {
        setPart(part, open: !openParts.contains(part))
    }

    private func setPart(_ part: CarPart, open: Bool) {
        if open { openParts.insert(part) } else { openParts.remove(part) }
        sceneView?.setPart(part, open: open)
    }

    func setWindows(_ open: Bool) {
        windowsOpen = open
        for part in Self.doorParts {
            sceneView?.setWindow(part, open: open)
        }
    }

    func toggleLights() {
        lightsOn.toggle()
        sceneView?.setLights(headlight: lightsOn, taillight: lightsOn)
    }

    func toggleWheels() {
        wheelsSpinning.toggle()
        if wheelsSpinning {
            sceneView?.startWheels(rpm: 5)
        } else {
            sceneView?.stopWheels()
        }
    }

    func resetView() {
        sceneView?.resetCamera()
    }

    // MARK: 真实车况同步

    /// 用真实车况驱动车模：闭锁/开锁（把手 + 门灯）、车窗、天窗。
    /// 只有状态值发生变化时才应用，避免把用户的本地预览覆盖掉。
    func syncStatus(doorUnlocked: Bool, windowOpen: Bool, sunroofOpen: Bool) {
        // 元组没有 Equatable 一致性，不能直接和可选元组比较：先解包再逐字段比
        if let last = lastSyncedStatus,
           last.unlocked == doorUnlocked, last.window == windowOpen, last.sunroof == sunroofOpen {
            return
        }
        lastSyncedStatus = (doorUnlocked, windowOpen, sunroofOpen)
        sceneView?.setUnlocked(doorUnlocked)
        setWindows(windowOpen)
        setPart(.sunroof, open: sunroofOpen)
    }
}

// MARK: - UIViewRepresentable（RealityKit + 智慧云控手势）

struct CarModel3DRepresentable: UIViewRepresentable {
    @ObservedObject var state: Car3DModelState
    let modelName: String

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> Car3DView {
        let view = Car3DView(frame: .zero)
        view.backgroundColor = .clear
        context.coordinator.view = view

        // 异步加载：glb 解析 + 贴图解码放后台线程（6MB 车模 + 25 个 PBR 材质，
        // 旧设备上同步加载可达数秒，会阻塞主线程让页面转场卡死甚至被系统看门狗杀掉）。
        // 完成后回主线程挂载；解析失败由 completeLoad 置位，UI 自动回退 2D 车图。
        let generation = state.beginLoad()
        let name = modelName
        Task.detached(priority: .userInitiated) {
            let build = Car3DView.buildCarModel(named: name)
            await MainActor.run {
                state.completeLoad(generation: generation, view: view, model: build)
            }
        }

        // 横向滑动 → 旋转车模（与 ScrollView 纵向滚动手势并存）
        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        // 捏合 → 缩放
        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        // 长按车身部件 → 直接开合（智慧云控「触控点控车」）
        let longPress = UILongPressGestureRecognizer(target: context.coordinator,
                                                     action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        longPress.allowableMovement = 12
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)

        // 双击 → 重置视角
        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        view.addGestureRecognizer(doubleTap)

        return view
    }

    func updateUIView(_ uiView: Car3DView, context: Context) {
        context.coordinator.view = uiView
        state.ensureAttached(uiView)
    }

    // MARK: 手势协调器

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let state: Car3DModelState
        weak var view: Car3DView?

        private enum PanDirection { case horizontal, vertical }
        private var panDirection: PanDirection?
        private var panStart: CGPoint = .zero
        private var lastX: CGFloat = 0

        init(state: Car3DModelState) {
            self.state = state
        }

        /// 与滚动/缩放手势并存：纵向滑动照常滚仪表盘，横向滑动旋转车模。
        /// 长按与双击保持独占，避免拖拽中误触发。
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            if gestureRecognizer is UILongPressGestureRecognizer || gestureRecognizer is UITapGestureRecognizer {
                return false
            }
            return other is UIPanGestureRecognizer || other is UIPinchGestureRecognizer
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view else { return }
            let point = gesture.location(in: view)
            switch gesture.state {
            case .began:
                panDirection = nil
                panStart = point
                lastX = point.x
            case .changed:
                if panDirection == nil {
                    let dx = abs(point.x - panStart.x)
                    let dy = abs(point.y - panStart.y)
                    if dx > 8 || dy > 8 {
                        panDirection = dx > dy ? .horizontal : .vertical
                    } else {
                        return   // 还没走出死区，等待
                    }
                }
                guard panDirection == .horizontal else { return }   // 纵向透传：ScrollView 滚页面
                let delta = Float(point.x - lastX) * 0.0085
                lastX = point.x
                view.setOrbit(azimuth: view.orbitAzimuth + delta)
            default:
                panDirection = nil
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard let view else { return }
            switch gesture.state {
            case .changed, .ended:
                let factor = Float(gesture.scale)
                guard factor > 0.01, factor < 100 else { return }
                view.setOrbit(radius: view.orbitRadius / factor)
                gesture.scale = 1.0
            default:
                break
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began, let view else { return }
            let point = gesture.location(in: view)
            guard let part = view.part(at: point) else { return }
            state.toggle(part)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            state.resetView()
        }
    }
}

// MARK: - 仪表盘车模舞台（3D 为主，可一键切回 2D 图）

struct CarVisual3DStage: View {
    let style: CarModelStyle
    let isUnlocked: Bool
    let windowOpen: Bool
    let sunroofOpen: Bool

    @StateObject private var model = Car3DModelState()
    @State private var show3D = true

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Group {
                    // 仅当当前车型有内置 3D 资产（style.model3DName != nil）时展示 3D，
                    // 其他车型自动回退 2D 车图
                    if show3D && !model.loadFailed, let name = style.model3DName {
                        ZStack {
                            CarModel3DRepresentable(state: model, modelName: name)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel("\(style.displayName) 三维车模，左右滑动可旋转，长按车门、尾门或天窗可开合")
                                .opacity(model.isLoaded ? 1 : 0)
                            if !model.isLoaded {
                                // 加载中：先用 2D 侧视图占位，后台解析完成后无缝替换为 3D
                                Image(style.sideImageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("正在加载\(style.displayName)三维车模")
                            }
                        }
                    } else {
                        Image(style.sideImageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(style.displayName) 车辆图片")
                    }
                }
                .frame(height: 200)

                // 3D / 2D 一键切换（延续 1.0.5 车模页习惯；无 3D 资产的车型不显示）
                if style.model3DName != nil {
                    Button {
                        show3D.toggle()
                    } label: {
                        Image(systemName: show3D ? "photo" : "square.stack.3d.up")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(WebTheme.muted)
                            .padding(7)
                            .background(Color(.secondarySystemBackground).opacity(0.82))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(show3D ? "切换为车辆图片" : "切换为三维车模")
                    .padding(6)
                }
            }

            if show3D && !model.loadFailed && model.isLoaded {
                controlStrip
            }
        }
        .compatOnChange(of: model.loadFailed) { failed in
            // 3D 加载失败：自动回退 2D 车图；用户点右上角按钮可手动重试加载
            if failed { show3D = false }
        }
        .compatOnChange(of: isUnlocked) { _ in syncStatus() }
        .compatOnChange(of: windowOpen) { _ in syncStatus() }
        .compatOnChange(of: sunroofOpen) { _ in syncStatus() }
        .onAppear { syncStatus() }
    }

    private func syncStatus() {
        model.syncStatus(doorUnlocked: isUnlocked, windowOpen: windowOpen, sunroofOpen: sunroofOpen)
    }

    // MARK: 智慧云控风格控制条（横向滚动）

    private var controlStrip: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // 部件芯片：按 CarPart 声明序排列，只显示模型里真实存在的部件
                    ForEach(CarPart.allCases.filter { model.availableParts.contains($0) }, id: \.self) { part in
                        partChip(part)
                    }
                    if model.hasWindows {
                        actionChip(title: "车窗", symbol: "arrow.down.to.line", active: model.windowsOpen) {
                            model.setWindows(!model.windowsOpen)
                        }
                    }
                    if model.hasLights {
                        actionChip(title: "车灯", symbol: "light.beacon.max", active: model.lightsOn) {
                            model.toggleLights()
                        }
                    }
                    if model.hasWheels {
                        actionChip(title: "车轮", symbol: "arrow.triangle.2.circlepath", active: model.wheelsSpinning) {
                            model.toggleWheels()
                        }
                    }
                    actionChip(title: "重置视角", symbol: "arrow.counterclockwise", active: false) {
                        model.resetView()
                    }
                }
            }
            Text(model.availableParts.isEmpty
                  ? "滑动旋转车模 · 双指捏合缩放 · 双击复位视角"
                  : "滑动旋转车模 · 长按车身部件直接开合")
                .font(.system(size: 9))
                .foregroundStyle(WebTheme.faint)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, 8)
    }

    private func partChip(_ part: CarPart) -> some View {
        let active = model.openParts.contains(part)
        return Button {
            model.toggle(part)
        } label: {
            chipLabel(title: part.rawValue, symbol: symbol(for: part), active: active)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(part.rawValue)\(active ? "，已开启" : "，已关闭")")
    }

    private func actionChip(title: String, symbol: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            chipLabel(title: title, symbol: symbol, active: active)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)\(active ? "，已开启" : "，已关闭")")
    }

    private func chipLabel(title: String, symbol: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(active ? .white : WebTheme.txt)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(active ? WebTheme.blue : WebTheme.card2)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(active ? WebTheme.blue : WebTheme.border, lineWidth: 1)
        )
    }

    private func symbol(for part: CarPart) -> String {
        switch part {
        case .doorFrontLeft:  return "arrow.up.left"
        case .doorFrontRight: return "arrow.up.right"
        case .doorRearLeft:   return "arrow.down.left"
        case .doorRearRight:  return "arrow.down.right"
        case .trunk:          return "arrow.up.backward"
        case .hood:           return "arrow.up.forward"
        case .sunroof:        return "sun.max"
        case .chargePort:     return "bolt.fill"
        }
    }
}
