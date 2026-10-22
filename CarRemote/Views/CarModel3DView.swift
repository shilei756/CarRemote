import SwiftUI
import SceneKit
import CarCore

// =============================================================
// 真实 3D 车模查看器（SceneKit）
// - 资源：OBJ + MTL + JPG（真实车型数据，Sketchfab CC-BY 免费模型转换：
//   逸动PLUS / UNI-V / CS75PLUS / UNI-K / CS75，6 万面 + 2048² 贴图）
// - 交互（参考「引力域」App 转台风格）：
//   · 单指左右拖拽 → 绕垂直轴顺时针/逆时针旋转（灵敏度刻意调低，松手带轻微惯性）
//   · 禁止上下旋转（仰角固定微俯视 10°，垂直拖拽让位给页面滚动）
//   · 双指捏合 → 缩放（限制在适配距离的 45%~180%）
// - 光照：低环境光保底 + 强主光塑形 + 弱补光，
//   避免白色车漆（如逸动PLUS 珠光白）过曝成纯白剪影
// =============================================================

// MARK: - SCNVector3 辅助

private extension SCNVector3 {
    static func - (a: SCNVector3, b: SCNVector3) -> SCNVector3 {
        SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z)
    }

    static func * (a: SCNVector3, s: Float) -> SCNVector3 {
        SCNVector3(a.x * s, a.y * s, a.z * s)
    }

    var length: Float { sqrt(x * x + y * y + z * z) }

    var normalized: SCNVector3 {
        let l = length
        return l > 0 ? SCNVector3(x / l, y / l, z / l) : self
    }

    func dot(_ o: SCNVector3) -> Float { x * o.x + y * o.y + z * o.z }
}

private func cross(_ a: SCNVector3, _ b: SCNVector3) -> SCNVector3 {
    SCNVector3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

// MARK: - 3D 视图

struct CarModel3DView: UIViewRepresentable {
    let modelName: String

    func makeUIView(context: Context) -> SCNView {
        let view = ModelSCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = false         // 自绘转台手势（仅水平旋转 + 捏合缩放）
        view.autoenablesDefaultLighting = false  // 改用手动三灯布光，避免白车漆过曝
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
        view.delegate = context.coordinator      // 逐帧驱动旋转惯性

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(CarModel3DView.Coordinator.handlePan(_:)))
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(CarModel3DView.Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)

        loadModel(into: view, modelName: modelName, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        if context.coordinator.loadedModel != modelName {
            loadModel(into: uiView, modelName: modelName, coordinator: context.coordinator)
        }
    }

    private func loadModel(into view: SCNView, modelName: String, coordinator: Coordinator) {
        guard let scene = SCNScene(named: "\(modelName).obj") else { return }
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.zNear = 0.1
        cameraNode.camera?.zFar = 200
        cameraNode.camera?.fieldOfView = 35          // 窄 FOV：长焦感、弱透视畸变
        scene.rootNode.addChildNode(cameraNode)
        addLights(to: scene.rootNode)
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geo = node.geometry else { return }
            for material in geo.materials {
                material.isDoubleSided = true       // 模型为单面壳，双面渲染
            }
        }
        view.scene = scene
        view.pointOfView = cameraNode
        coordinator.loadedModel = modelName
        coordinator.cameraNode = cameraNode
        coordinator.scene = scene
        coordinator.resetCamera()                   // 方位角/惯性归位到初始 3/4 视角
        if let modelView = view as? ModelSCNView {
            modelView.coordinator = coordinator
        }
        Self.fitCamera(in: view, coordinator: coordinator)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 三灯布光：环境光只做保底（130）让暗部不死黑；
    /// 右前上主光（720）塑形，左后补光（140）提暗部。
    /// 白色车漆在强环境光下会过曝成纯白剪影（实测均值 >240、过半像素死白），
    /// 压低环境光后白色漆面保持 170~200 且明暗层次清晰，深色车窗/轮毂同步凸显。
    private func addLights(to root: SCNNode) {
        func lightNode(_ type: SCNLight.LightType, intensity: CGFloat, position: SCNVector3) -> SCNNode {
            let light = SCNLight()
            light.type = type
            light.intensity = intensity
            light.castsShadow = false
            let node = SCNNode()
            node.light = light
            node.position = position
            return node
        }
        root.addChildNode(lightNode(.ambient, intensity: 130, position: SCNVector3Zero))
        root.addChildNode(lightNode(.directional, intensity: 720, position: SCNVector3(3, 5, 4)))
        root.addChildNode(lightNode(.directional, intensity: 140, position: SCNVector3(-4, 1, -2)))
    }

    /// 按模型包围盒投影自动拟合相机距离（保持当前旋转角度，仅精算距离）：
    /// 使车模约占画面 90%（任意视口宽高比自适应，车模始终与 2D 图片观感一致地充满画布）
    static func fitCamera(in view: SCNView, coordinator: Coordinator) {
        guard let cameraNode = coordinator.cameraNode,
              let camera = cameraNode.camera,
              let scene = coordinator.scene,
              view.bounds.width > 1, view.bounds.height > 1 else { return }
        // 收集所有几何节点的世界坐标包围盒 8 角点
        var corners: [SCNVector3] = []
        scene.rootNode.enumerateChildNodes { node, _ in
            guard node.geometry != nil else { return }
            let (bmin, bmax) = node.boundingBox
            let m = node.worldTransform
            for i in 0..<8 {
                let c = SCNVector3(
                    i & 1 != 0 ? bmax.x : bmin.x,
                    i & 2 != 0 ? bmax.y : bmin.y,
                    i & 4 != 0 ? bmax.z : bmin.z
                )
                corners.append(SCNVector3(
                    m.m11 * c.x + m.m21 * c.y + m.m31 * c.z + m.m41,
                    m.m12 * c.x + m.m22 * c.y + m.m32 * c.z + m.m42,
                    m.m13 * c.x + m.m23 * c.y + m.m33 * c.z + m.m43
                ))
            }
        }
        guard !corners.isEmpty else { return }
        let target = SCNVector3Zero
        // 视线方向由当前方位角 + 固定仰角决定；相机仅沿视线方向移动时，
        // right/up 投影与距离无关，一次精算即可
        let el = Coordinator.initialElevation
        let ce = cos(el)
        let fwd = SCNVector3(-ce * sin(coordinator.azimuth), -sin(el), -ce * cos(coordinator.azimuth)).normalized
        let right = cross(fwd, SCNVector3(0, 1, 0)).normalized
        let up = cross(right, fwd).normalized
        var maxW: Float = 0
        var maxH: Float = 0
        for c in corners {
            let v = c - target
            maxW = max(maxW, abs(v.dot(right)))
            maxH = max(maxH, abs(v.dot(up)))
        }
        let aspect = Float(view.bounds.width / view.bounds.height)
        let vfov = Float(camera.fieldOfView) * .pi / 180
        let hfov = 2 * atan(tan(vfov / 2) * aspect)
        let fill: Float = 0.90
        let z = max(maxW / (tan(hfov / 2) * fill), maxH / (tan(vfov / 2) * fill))
        // 视口尺寸变化时保留用户的捏合缩放比例
        let zoom = coordinator.fitDistance > 0 ? coordinator.distance / coordinator.fitDistance : 1
        coordinator.fitDistance = z
        coordinator.distance = z * zoom
        coordinator.applyCamera()
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate, UIGestureRecognizerDelegate {
        var loadedModel: String?
        var cameraNode: SCNNode?
        var scene: SCNScene?

        // MARK: 转台状态

        static let initialAzimuth: Float = 10 * .pi / 180    // 初始方位角：略偏车头的 3/4 视角
        static let initialElevation: Float = 10 * .pi / 180  // 固定仰角：微俯视，交互中不变化
        static let panSensitivity: Float = 0.004             // rad/pt：刻意低速，参考引力域转台手感
        static let spinDecay: Float = 2.4                    // 松手后惯性衰减系数 /s
        static let maxSpin: Float = 8.0                      // 惯性角速度上限 rad/s

        var azimuth: Float = Coordinator.initialAzimuth
        var distance: Float = 10          // 当前相机到目标距离（捏合缩放改变）
        var fitDistance: Float = 10       // 自动适配得到的基准距离
        var spinVelocity: Float = 0       // 松手后的残余角速度 rad/s
        private var lastPanX: CGFloat = 0
        private var lastPanTime: TimeInterval = 0
        private var lastFrameTime: TimeInterval?

        func resetCamera() {
            azimuth = Self.initialAzimuth
            spinVelocity = 0
            applyCamera()
        }

        /// 按当前方位角/仰角/距离摆放相机（目标为原点，look(at:) 保持微俯视）
        func applyCamera() {
            guard let cameraNode = cameraNode else { return }
            let el = Self.initialElevation
            let ce = cos(el)
            cameraNode.position = SCNVector3(
                distance * ce * sin(azimuth),
                distance * sin(el),
                distance * ce * cos(azimuth)
            )
            cameraNode.look(at: SCNVector3Zero)
        }

        // MARK: 手势

        /// 单指水平拖拽 → 绕 Y 轴旋转（仅水平方向，顺时针/逆时针由拖动方向决定）
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            switch gesture.state {
            case .began:
                spinVelocity = 0
                lastPanX = gesture.location(in: gesture.view).x
                lastPanTime = CACurrentMediaTime()
            case .changed:
                let x = gesture.location(in: gesture.view).x
                let now = CACurrentMediaTime()
                let dx = Float(x - lastPanX)
                let dt = Float(max(now - lastPanTime, 1.0 / 120))
                lastPanX = x
                lastPanTime = now
                let dAz = dx * Self.panSensitivity
                azimuth += dAz
                spinVelocity = dAz / dt          // 记录瞬时角速度，供松手后惯性使用
                applyCamera()
            case .ended, .cancelled:
                spinVelocity = min(max(spinVelocity, -Self.maxSpin), Self.maxSpin)
            default:
                break
            }
        }

        /// 双指捏合 → 缩放（向外靠近、向内拉远，钳制在基准距离的 45%~180%）
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            guard gesture.state == .began || gesture.state == .changed else { return }
            let scale = Float(gesture.scale)
            guard scale > 0 else { return }
            distance = distance / scale
            distance = min(max(distance, fitDistance * 0.45), fitDistance * 1.8)
            gesture.scale = 1.0
            applyCamera()
        }

        // MARK: 惯性（渲染循环逐帧衰减）

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            defer { lastFrameTime = time }
            guard let last = lastFrameTime else { return }
            let dt = Float(min(max(time - last, 0), 0.1))
            guard dt > 0, abs(spinVelocity) > 0.001 else { return }
            azimuth += spinVelocity * dt
            spinVelocity *= exp(-Self.spinDecay * dt)
            if abs(spinVelocity) <= 0.001 { spinVelocity = 0 }
            applyCamera()
        }

        // MARK: UIGestureRecognizerDelegate

        /// 仅水平拖拽启动旋转；垂直拖拽让位给仪表盘 ScrollView 滚动
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.2
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

/// SCNView 子类：首次布局后 bounds 才有效，视口尺寸变化时重新拟合相机；
/// 进入窗口时把外层 ScrollView 的滚动手势挂到车模旋转手势之后
/// （水平拖动转车模、垂直拖动滚页面，两者不打架）
final class ModelSCNView: SCNView {
    weak var coordinator: CarModel3DView.Coordinator?
    private var lastFitSize: CGSize = .zero
    private var didConfigureGestures = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard !didConfigureGestures, window != nil else { return }
        didConfigureGestures = true
        guard let pan = gestureRecognizers?.first(where: { $0 is UIPanGestureRecognizer }) else { return }
        var ancestor: UIView? = superview
        while let v = ancestor {
            if let scroll = v as? UIScrollView {
                scroll.panGestureRecognizer.require(toFail: pan)
                break
            }
            ancestor = v.superview
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if abs(bounds.width - lastFitSize.width) > 0.5 || abs(bounds.height - lastFitSize.height) > 0.5 {
            lastFitSize = bounds.size
            guard let coordinator = coordinator else { return }
            CarModel3DView.fitCamera(in: self, coordinator: coordinator)
        }
    }
}

// MARK: - 仪表盘车模（3D 为主，可切换回 2D 图片）

struct CarVisual3DView: View {
    let style: CarModelStyle
    let isUnlocked: Bool
    @State private var show3D: Bool = true

    private var hasModel: Bool {
        Bundle.main.url(forResource: style.model3DName, withExtension: "obj") != nil
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if show3D && hasModel {
                CarModel3DView(modelName: style.model3DName)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(style.sideImageName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
            if hasModel {
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
                .accessibilityLabel(show3D ? "切换为图片" : "切换为三维模型")
                .padding(8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isUnlocked
            ? "\(style.displayName) 车辆三维模型，当前已解锁，左右拖拽可旋转查看"
            : "\(style.displayName) 车辆三维模型，当前已锁止")
    }
}
