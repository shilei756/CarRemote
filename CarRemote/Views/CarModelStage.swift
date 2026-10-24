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
//   - 车模随真实车况自动同步（1.1.4 起）：
//       · 车门：逐扇独立。未锁的车门在车模上呈开启状态
//         （接口 `leftFrontDoorStatus` / `rightFrontDoorStatus` /
//           `leftRearDoorStatus` / `rightRearDoorStatus` / `trunk` / `hood`，
//           取值 1 = 该门已解锁）
//       · 车窗：逐扇独立。未关的车窗在车模上降下
//         （接口 `diverWindow`(主驾) / `passengerWindow`(副驾) /
//           `leftRearWindow` / `rightRearWindow`，取值 1 = 未关）
//       · 天窗：`sunroof` 字段
//   - 车模下方**不再提供手动开门/开窗按钮**：车门车窗完全由真实车况驱动，
//     避免「本机预览」与真实车况互相打架（长安远程指令没有单门/单窗控制接口）。
//
// 注意：车门车窗的联动以「刷新车况」为准，刷新后车模自动回归真实状态。
// =============================================================

// MARK: - 车模状态（单一数据源）

final class Car3DModelState: ObservableObject {
    /// 开启中的部件（车门 / 尾门 / 天窗）
    @Published private(set) var openParts: Set<CarPart> = []
    /// 是否存在未关的车窗（全车聚合，仅用于 UI 展示）
    @Published private(set) var windowsOpen = false
    /// 车灯是否点亮（1.1.4 起：**由真实车况驱动**——车辆已启动才亮灯，熄火即灭灯）
    @Published private(set) var lightsOn = false
    /// 车轮是否转动（1.1.4 起：**由真实车况驱动**——行驶中才滚动，静止不动）
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
    private var lastSyncedStatus: CarStatus.DoorsAndWindows?

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
            applyStatus(last, to: view, duration: 0.001)
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

    // MARK: 部件控制（触控点控车的本地预览）

    func toggle(_ part: CarPart) {
        setPart(part, open: !openParts.contains(part))
    }

    private func setPart(_ part: CarPart, open: Bool) {
        if open { openParts.insert(part) } else { openParts.remove(part) }
        sceneView?.setPart(part, open: open)
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

    // MARK: 车辆启停 / 行驶状态同步（灯与车轮完全由真实车况驱动）

    /// 车辆已启动 → 点亮大灯；车辆行驶中 → 车轮滚动。
    /// 车辆静止（未启动/未行驶）时车模必须完全静止且不亮灯，
    /// 否则会出现「车况正常但车轮在转、大灯常亮」的违和感（1.1.4 实机反馈）。
    func syncVehicleState(started: Bool, driving: Bool) {
        if lightsOn != started {
            lightsOn = started
            sceneView?.setLights(headlight: started, taillight: started)
        }
        if wheelsSpinning != driving {
            wheelsSpinning = driving
            if driving {
                sceneView?.startWheels(rpm: 5)
            } else {
                sceneView?.stopWheels()
            }
        }
    }

    // MARK: 真实车况同步

    /// 用真实车况驱动车模：逐扇车门（未锁即呈开启态）+ 逐扇车窗（未关即降下）+ 天窗。
    /// 只有状态值发生变化时才应用，避免把用户的本地预览覆盖掉。
    func syncStatus(_ status: CarStatus.DoorsAndWindows) {
        if let last = lastSyncedStatus, last == status { return }
        lastSyncedStatus = status
        guard let view = sceneView else { return }
        applyStatus(status, to: view, duration: 0.45)
    }

    /// 把逐门逐窗状态落到车模实体上
    private func applyStatus(_ s: CarStatus.DoorsAndWindows, to view: Car3DView, duration: TimeInterval) {
        // 车门：未锁 → 车模上开启（逐扇独立）
        let doors: [(CarPart, Bool)] = [
            (.doorFrontLeft,  s.leftFrontDoorUnlocked),
            (.doorFrontRight, s.rightFrontDoorUnlocked),
            (.doorRearLeft,   s.leftRearDoorUnlocked),
            (.doorRearRight,  s.rightRearDoorUnlocked),
            (.trunk,          s.trunkUnlocked),
            (.hood,           s.hoodUnlocked)
        ]
        for (part, unlocked) in doors {
            if openParts.contains(part) != unlocked {
                if unlocked { openParts.insert(part) } else { openParts.remove(part) }
            }
            // 车况驱动时车窗不跟随车门（车窗只由车窗状态字段决定）
            view.setPartFromStatus(part, open: unlocked, duration: duration)
        }

        // 车窗：未关 → 降下（逐扇独立）
        let windows: [(CarPart, Bool)] = [
            (.doorFrontLeft,  s.leftFrontWindowOpen),
            (.doorFrontRight, s.rightFrontWindowOpen),
            (.doorRearLeft,   s.leftRearWindowOpen),
            (.doorRearRight,  s.rightRearWindowOpen)
        ]
        for (part, open) in windows {
            view.setWindow(part, open: open, duration: duration)
        }
        windowsOpen = s.anyWindowOpen

        // 天窗
        if openParts.contains(.sunroof) != s.sunroofOpen {
            if s.sunroofOpen { openParts.insert(.sunroof) } else { openParts.remove(.sunroof) }
        }
        view.setPartFromStatus(.sunroof, open: s.sunroofOpen, duration: duration)

        // 门灯 / 把手：任一门未锁即点亮
        view.setUnlocked(s.anyDoorUnlocked)
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
                // 取反：RealityKit 轨道相机 azimuth 增大时车模视觉上向右转，
                // 与「拖动车模跟随手指」的自然预期相反（1.1.3 实机反馈）
                let delta = -Float(point.x - lastX) * 0.0085
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
                // 捏合缩放：直接缩放固定相机距离（>1 拉近放大，<1 推远缩小）。
                // 相机距离不随旋转角度变化 —— 保持「车原地转、镜头固定」的姿态。
                view.zoom(by: factor)
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
    /// 真实车况中的门窗状态（逐门逐窗）
    let doorsAndWindows: CarStatus.DoorsAndWindows
    /// 车辆是否已启动（点火）→ 决定大灯是否点亮
    let vehicleStarted: Bool
    /// 车轮是否应当滚动（行驶中；接口不上报车速时退化为「已启动」）
    let wheelsRolling: Bool

    /// 展示模式：3D 车模 / 2D 车图（1.1.4 起右上角胶囊滑块切换）
    private enum StageMode { case threeD, twoD }

    @StateObject private var model = Car3DModelState()
    @State private var mode: StageMode = .threeD

    private var show3D: Bool { mode == .threeD }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
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
                                // 加载中：先用 2D 车图占位，后台解析完成后无缝替换为 3D
                                Image(style.sideImageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel("正在加载\(style.displayName)三维车模")
                            }
                        }
                    } else {
                        // 2D 档（1.1.4 用户反馈：「俯视改为 2D 之前的车图」）：
                        // 直接显示各车型的 2D 侧视大图（与网页版 /static/img/*_side.png 同源），
                        // 不再渲染俯视小图，避免与 3D 车模视觉割裂。
                        Image(style.sideImageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(style.displayName) 二维车辆图片")
                    }
                }
                // 1.1.4：舞台高度保持 200pt（与 1.1.3 / b102 一致）。
                // 车模大小由「固定相机距离」决定（车原地转、镜头不动），
                // 不做自动取景，因此不需要为「整车完整入画」而加高舞台 ——
                // 加高反而会让车模在画面里显得更小。
                .frame(height: 200)

                HStack(alignment: .top) {
                    // 重置视角：放在「我的爱车」标题正下方（1.1.4 用户反馈）
                    if show3D && !model.loadFailed && style.model3DName != nil {
                        Button {
                            model.resetView()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10, weight: .semibold))
                                Text("重置视角")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(WebTheme.txt)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Color(.secondarySystemBackground).opacity(0.85))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(WebTheme.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("重置车模视角")
                    }
                    Spacer()
                    // 3D / 2D 胶囊滑块（对齐智慧云控车模页右上角切换控件）
                    if style.model3DName != nil {
                        stageModeSlider
                    }
                }
                .padding(.horizontal, 2)
                .padding(.top, 2)
            }

            if show3D && !model.loadFailed && model.isLoaded {
                controlStrip
            }
        }
        .compatOnChange(of: model.loadFailed) { failed in
            // 3D 加载失败：自动回退 2D 车图；「重置视角/3D」滑块仍可手动重试加载
            if failed { mode = .twoD }
        }
        .compatOnChange(of: doorsAndWindows) { _ in syncStatus() }
        .compatOnChange(of: vehicleStarted) { _ in syncVehicleState() }
        .compatOnChange(of: wheelsRolling) { _ in syncVehicleState() }
        .onAppear {
            syncStatus()
            syncVehicleState()
        }
    }

    private func syncStatus() {
        model.syncStatus(doorsAndWindows)
    }

    private func syncVehicleState() {
        model.syncVehicleState(started: vehicleStarted, driving: wheelsRolling)
    }

    // MARK: 3D / 2D 胶囊滑块

    private var stageModeSlider: some View {
        HStack(spacing: 0) {
            stageSegment(.threeD, title: "3D")
            stageSegment(.twoD, title: "2D")
        }
        .padding(3)
        .background(Color(.secondarySystemBackground).opacity(0.9))
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(WebTheme.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("车模展示模式")
        .accessibilityHint("可在三维车模与二维车图之间切换")
    }

    private func stageSegment(_ segment: StageMode, title: String) -> some View {
        let selected = mode == segment
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { mode = segment }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? Color.white : WebTheme.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(selected ? WebTheme.blue : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "3D" ? "三维车模" : "二维车图")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: 车况联动说明

    private var controlStrip: some View {
        VStack(spacing: 6) {
            // 车况联动状态摘要：告诉用户当前车模反映的是真实车况
            statusSummary
            Text("滑动旋转车模 · 双指捏合缩放 · 双击复位视角")
                .font(.system(size: 9))
                .foregroundStyle(WebTheme.faint)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.top, 8)
    }

    /// 车况联动摘要（逐门逐窗）
    private var statusSummary: some View {
        let s = doorsAndWindows
        var unlocked: [String] = []
        if s.leftFrontDoorUnlocked { unlocked.append("左前门") }
        if s.rightFrontDoorUnlocked { unlocked.append("右前门") }
        if s.leftRearDoorUnlocked { unlocked.append("左后门") }
        if s.rightRearDoorUnlocked { unlocked.append("右后门") }
        if s.trunkUnlocked { unlocked.append("后备箱") }
        if s.hoodUnlocked { unlocked.append("机盖") }
        var openWindows: [String] = []
        if s.leftFrontWindowOpen { openWindows.append("左前窗") }
        if s.rightFrontWindowOpen { openWindows.append("右前窗") }
        if s.leftRearWindowOpen { openWindows.append("左后窗") }
        if s.rightRearWindowOpen { openWindows.append("右后窗") }
        if s.sunroofOpen { openWindows.append("天窗") }

        let text: String
        if unlocked.isEmpty && openWindows.isEmpty {
            text = "车模与实车一致：车门已锁、车窗已关"
        } else {
            var parts: [String] = []
            if !unlocked.isEmpty { parts.append("未锁：" + unlocked.joined(separator: "、")) }
            if !openWindows.isEmpty { parts.append("未关：" + openWindows.joined(separator: "、")) }
            text = parts.joined(separator: "　")
        }
        // 追加「灯 / 车轮」状态，让用户明确知道车模的动态是由车况驱动的
        let dyn = wheelsRolling ? "行驶中，车轮转动"
            : (vehicleStarted ? "已启动，车灯点亮" : "未启动，车灯熄灭、车轮静止")
        return Text(text + "　·　" + dyn)
            .font(.system(size: 10))
            .foregroundStyle(WebTheme.muted)
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel(text + "，" + dyn)
    }
}
