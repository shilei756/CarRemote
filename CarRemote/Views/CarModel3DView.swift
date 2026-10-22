import SwiftUI
import SceneKit

// =============================================================
// 真实 3D 车模查看器（SceneKit）
// - 资源：OBJ + MTL + PNG（CC0，Kenney Car Kit / Kay Lousberg，按车型映射）
// - 交互：手指拖拽旋转、双指捏合缩放；无自动动画（纯用户驱动）
// - 透传 SceneKit 原生加载，零外部依赖，避免引入 Swift 包带来的构建风险
// =============================================================

struct CarModel3DView: UIViewRepresentable {
    let modelName: String

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
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
        cameraNode.position = SCNVector3(0, 1.6, 5.5)
        cameraNode.look(at: SCNVector3Zero)
        scene.rootNode.addChildNode(cameraNode)
        scene.rootNode.enumerateChildNodes { node, _ in
            guard let geo = node.geometry else { return }
            geo.materials = geo.materials.map { material in
                material.isDoubleSided = true
                return material
            }
        }
        view.scene = scene
        view.pointOfView = cameraNode
        view.defaultCameraController.target = SCNVector3Zero
        coordinator.loadedModel = modelName
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var loadedModel: String?
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
