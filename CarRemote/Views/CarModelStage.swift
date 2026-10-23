import SwiftUI
import SceneKit
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

    private weak var sceneView: Car3DView?

    /// 最近一次同步的真实车况（值没变就不动车模，避免覆盖用户的本地预览）
    private var lastSyncedStatus: (unlocked: Bool, window: Bool, sunroof: Bool)?

    private static let doorParts: [CarPart] = [.doorFrontLeft, .doorFrontRight, .doorRearLeft, .doorRearRight]

    // MARK: 挂载

    func attach(_ view: Car3DView) {
        sceneView = view
        availableParts = view.availableParts
        hasWindows = view.hasWindows
        // 视图重建后把当前开合态应用回去
        for part in openParts { view.setPart(part, open: true, duration: 0.001) }
        if windowsOpen {
            for part in Self.doorParts { view.setWindow(part, open: true, duration: 0.001) }
        }
        view.setLights(headlight: lightsOn, taillight: lightsOn)
        if wheelsSpinning { view.startWheels(rpm: 5) } else { view.stopWheels() }
    }

    func ensureAttached(_ view: Car3DView) {
        if sceneView !== view { attach(view) }
    }

    func detach() {
        sceneView = nil
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

// MARK: - UIViewRepresentable（SceneKit + 智慧云控手势）

struct CarModel3DRepresentable: UIViewRepresentable {
    @ObservedObject var state: Car3DModelState
    let modelName: String

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    func makeUIView(context: Context) -> Car3DView {
        let view = Car3DView(frame: .zero)
        view.backgroundColor = .clear
        view.loadModel(named: modelName)
        state.attach(view)
        context.coordinator.view = view

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
            let options: [SCNHitTestOption: Any] = [.firstFoundOnly: true]
            guard let hit = view.hitTest(point, options: options).first,
                  let part = view.part(containing: hit.node) else { return }
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

    private let modelName = "EadoPlus2022"

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if show3D {
                        CarModel3DRepresentable(state: model, modelName: modelName)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(style.displayName) 三维车模，左右滑动可旋转，长按车门、尾门或天窗可开合")
                    } else {
                        Image(style.sideImageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(style.displayName) 车辆图片")
                    }
                }
                .frame(height: 200)

                // 3D / 2D 一键切换（延续 1.0.5 车模页习惯）
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

            if show3D {
                controlStrip
            }
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
                    actionChip(title: "车灯", symbol: "light.beacon.max", active: model.lightsOn) {
                        model.toggleLights()
                    }
                    actionChip(title: "车轮", symbol: "arrow.triangle.2.circlepath", active: model.wheelsSpinning) {
                        model.toggleWheels()
                    }
                    actionChip(title: "重置视角", symbol: "arrow.counterclockwise", active: false) {
                        model.resetView()
                    }
                }
            }
            Text("滑动旋转车模 · 长按车身部件直接开合")
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
