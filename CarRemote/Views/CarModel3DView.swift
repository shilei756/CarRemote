import SwiftUI
import SceneKit
import CarCore

// =============================================================
// 真实 3D 车模查看器（SceneKit）
// - 资源：OBJ + MTL + JPG（真实车型数据，Sketchfab CC-BY 免费模型转换：
//   逸动PLUS / UNI-V / CS75PLUS / UNI-K / CS75，6 万面 + 2048² 贴图）
// - 交互：手指拖拽旋转、双指捏合缩放；无自动动画（纯用户驱动）
// - 透传 SceneKit 原生加载，零外部依赖，避免引入 Swift 包带来的构建风险
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
        view.allowsCameraControl = true           // 手动旋转 / 捏合缩放，无自动动画
        view.autoenablesDefaultLighting = true     // 自带灯光，保证模型可见
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 30
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
        // 初始机位：3/4 侧视——方位角 10°（略偏车头）、仰角 10°（微俯视）
        let az = Float(10) * .pi / 180
        let el = Float(10) * .pi / 180
        let dir = SCNVector3(cos(el) * cos(az), sin(el), cos(el) * sin(az))
        cameraNode.position = dir * 100             // 先放远处，fitCamera 精算距离
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChild(cameraNode)
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geo = node.geometry else { return }
            for material in geo.materials {
                material.isDoubleSided = true       // 模型为单面壳，双面渲染
            }
        }
        view.scene = scene
        view.pointOfView = cameraNode
        view.defaultCameraController.target = SCNVector3Zero
        coordinator.loadedModel = modelName
        coordinator.cameraNode = cameraNode
        coordinator.scene = scene
        if let modelView = view as? ModelSCNView {
            modelView.coordinator = coordinator
        }
        Self.fitCamera(in: view, coordinator: coordinator)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// 按模型包围盒投影自动拟合相机距离：
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
        let fwd = (target - cameraNode.position).normalized
        let right = cross(fwd, SCNVector3(0, 1, 0)).normalized
        let up = cross(right, fwd).normalized
        // 相机仅沿视线方向移动时，right/up 投影与距离无关，一次精算即可
        var maxW: Float = 0
        var maxH: Float = 0
        for c in corners {
            let v = c - cameraNode.position
            maxW = max(maxW, abs(v.dot(right)))
            maxH = max(maxH, abs(v.dot(up)))
        }
        let aspect = Float(view.bounds.width / view.bounds.height)
        let vfov = Float(camera.fieldOfView) * .pi / 180
        let hfov = 2 * atan(tan(vfov / 2) * aspect)
        let fill: Float = 0.90
        let z = max(maxW / (tan(hfov / 2) * fill), maxH / (tan(vfov / 2) * fill))
        cameraNode.position = target - fwd * z
        cameraNode.look(at: target)
    }

    final class Coordinator {
        var loadedModel: String?
        var cameraNode: SCNNode?
        var scene: SCNScene?
    }
}

/// SCNView 子类：首次布局后 bounds 才有效，视口尺寸变化时重新拟合相机
final class ModelSCNView: SCNView {
    weak var coordinator: CarModel3DView.Coordinator?
    private var lastFitSize: CGSize = .zero

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
            ? "\(style.displayName) 车辆三维模型，当前已解锁，可拖拽旋转查看"
            : "\(style.displayName) 车辆三维模型，当前已锁止")
    }
}
