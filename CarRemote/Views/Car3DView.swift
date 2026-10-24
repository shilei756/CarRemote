//
//  Car3DView.swift
//  长安控车 — 3D 车模组件（RealityKit）
//
//  适配车型：逸动PLUS 2022（内部代号 C211，官方 3D 车模，来自长安智慧云控 App 安装包）
//
//  渲染管线（1.1.3 起由 SceneKit 重写而来）：
//    - 资产由 glb 离线转换而来：EadoPlus2022.rk.json（材质/部件/分组/动画目标位/归一化参数）
//      + EadoPlus2022.rk.bin（Float32 顶点/法线/UV + UInt32 索引）+ tex/*.png（9 张内嵌贴图）。
//    - 运行时按功能分组烘焙几何（顶点已烘焙到「最近功能分组原点」的局部空间），
//      用 MeshDescriptor + MeshResource.generate 重建网格，PhysicallyBasedMaterial 还原 PBR。
//    - 用 Apple 原生 RealityKit（非弃用框架），在 iOS 15+ 全员可用，
//      规避 iOS 26/27 上 SceneKit(SCNView) 创建即崩溃的问题（录屏实证）。
//
//  功能（与旧版 1:1 对齐）：
//    - 四门开/关（官方 75° 铰链旋转，绕节点局部 Y 轴，枢轴=节点原点）
//    - 后备箱开/关（官方 70° 绕局部 X 轴）
//    - 天窗开/关（官方后滑 + 7.1° 翻转）
//    - 四门车窗随车门升降（官方下行动画，含 3° 微倾）
//    - 门把手弹出/收回（官方 10° 翻转，解锁时联动）
//    - 灯光控制：前灯/DRL/示宽/尾灯/刹车灯（官方 LOn 自发光网格显隐）
//    - 车轮持续转动
//    - 轨道相机：滑动旋转 / 捏合缩放 / 重置视角（由外层 SwiftUI 手势驱动）
//
//  用法（SwiftUI）：
//    struct Car3DRepresentable: UIViewRepresentable {
//        func makeUIView(context: Context) -> Car3DView { Car3DView() }
//        func updateUIView(_ v: Car3DView, context: Context) { }
//    }
//

import UIKit
import RealityKit
import Combine

// MARK: - 可控部件

public enum CarPart: String, CaseIterable {
    case doorFrontLeft  = "左前门"
    case doorFrontRight = "右前门"
    case doorRearLeft   = "左后门"
    case doorRearRight  = "右后门"
    case trunk          = "后备箱"
    case hood           = "机盖"
    case sunroof        = "天窗"
    case chargePort     = "充电口"
}

public enum WheelPosition: String, CaseIterable {
    case frontLeft, frontRight, rearLeft, rearRight
}

// MARK: - 资产清单（由 glb2rk.py 生成，结构与 Python 端严格对齐）

private struct RKNormalization: Codable {
    let scale: Double
    let center: [Double]
    let minY: Double
    let length: Double
}

private struct RKMaterialDef: Codable {
    let name: String
    let texture: String?
    let baseColorSRGB: [Double]
    let metallic: Double
    let roughness: Double
    let emissiveSRGB: [Double]?
    let blend: Bool
    let doubleSided: Bool
}

private struct RKPartDef: Codable {
    let name: String
    let group: String
    let material: Int
    let vertexCount: Int
    let indexCount: Int
    let positionOffset: Int
    let normalOffset: Int?
    let uvOffset: Int?
    let indexOffset: Int
    let hasNormal: Bool
    let hasUV: Bool
    let isLight: Bool
}

private struct RKGroupDef: Codable {
    let position: [Double]
    let parent: String?
    let kind: String
    let key: String?
    let openPosition: [Double]?
    let openTiltDeg: Double?
    let wheelKey: String?
}

private struct RKManifest: Codable {
    let format: String
    let uvFlipV: Bool
    let normalization: RKNormalization
    let materials: [RKMaterialDef]
    let geometryFile: String
    let parts: [RKPartDef]
    let groups: [String: RKGroupDef]
    let lightGroups: [String: [String]]
    let stats: [String: Int]
}

// 灯光分组（对应 C211 官方 LOn 自发光网格命名）
public enum LightGroup: String, CaseIterable {
    case headlight
    case taillight
    case brake
    case doorLight
}

// MARK: - 构建产物（后台解析完成后由主线程挂入场景）

public struct RKCarModel {
    let root: Entity
    let partEntities: [CarPart: Entity]          // 门/尾门/天窗的父实体（旋转枢轴所在）
    let windowEntities: [CarPart: Entity]        // 车窗组实体（门子节点）
    let handleEntities: [CarPart: Entity]        // 把手组实体（门子节点）
    let wheelEntities: [WheelPosition: Entity]   // 后轮左右共用同一实体
    let uniqueWheels: [Entity]                   // 去重后的车轮实体（用于转动）
    let lightEntities: [LightGroup: [Entity]]
    let doorTilt: [CarPart: Float]               // 弧度：±75°(门) / 70°(尾门)
    let sunroofRest: SIMD3<Float>
    let sunroofOpen: SIMD3<Float>
    let sunroofTilt: Float
    let windowRest: [CarPart: SIMD3<Float>]      // 门局部坐标系下的关闭位
    let windowOpen: [CarPart: SIMD3<Float>]      // 门局部坐标系下的开启位
    let windowTilt: [CarPart: Float]
    let handleTilt: [CarPart: Float]
    /// 车模世界坐标包围盒（min/max），用于相机自动取景：
    /// 旋转到任意角度时都能算出「刚好容纳整车」的相机距离，避免车身被视口裁切。
    let boundsMin: SIMD3<Float>
    let boundsMax: SIMD3<Float>
}

// MARK: - 车模视图

public final class Car3DView: UIView {

    // MARK: 公开状态

    public private(set) var partAngles: [CarPart: Float] = [:]
    public private(set) var isWheelsSpinning = false
    public var lowerWindowsWithDoors = true
    public private(set) var isUnlocked = false
    public private(set) var availableParts: Set<CarPart> = []
    public private(set) var hasWindows = false
    /// 模型是否带可点亮的灯光件（Eado 官方模有；外购单 mesh 模没有）
    public private(set) var hasLights = false
    /// 模型是否带可转动的车轮件
    public private(set) var hasWheels = false

    /// 轨道方位角（弧度；0 = 车头正对屏幕右前方，增大 = 车身左转）
    public private(set) var orbitAzimuth: Float = Car3DView.defaultAzimuth
    /// 轨道仰角（弧度，钳制 0.03~1.15）
    public private(set) var orbitElevation: Float = Car3DView.defaultElevation
    /// 轨道半径（场景单位，钳制 1.4~10；默认值以车模占屏与 2D 车图一致为准）
    public private(set) var orbitRadius: Float = Car3DView.defaultRadius
    /// 轨道注视点（车身中部）
    public private(set) var orbitTarget = SIMD3<Float>(0, 0.36, 0)

    private static let defaultAzimuth: Float = .pi / 2   // 初始视角：车身正侧面（车头朝左）
    private static let defaultElevation: Float = 0.2514
    // 初始相机距离：1.1.4 用户要求「把逸动 3D 车模稍微放大一点」，
    // 由 2.4 收到 2.12（约放大 13%），车模在 200pt 高的舞台里占比更合适。
    private static let defaultRadius: Float = 2.12

    // MARK: 私有

    private var arView: ARView!
    private var cameraEntity: PerspectiveCamera?
    private var sceneAnchor: AnchorEntity?
    private var carRoot: Entity?
    /// 车模世界包围盒（自动取景用）；模型挂载后更新
    private var modelBoundsMin = SIMD3<Float>(repeating: 0)
    private var modelBoundsMax = SIMD3<Float>(repeating: 0)
    private var hasModelBounds = false
    /// 用户手势缩放倍率（1 = 自动取景距离；>1 更近更大，<1 更远更小）
    private var userZoom: Float = 1.0
    /// 上次取景时的视口尺寸（用于检测尺寸变化并重新取景）
    private var lastFramedSize: CGSize = .zero
    private var partEntities: [CarPart: Entity] = [:]
    private var windowEntities: [CarPart: Entity] = [:]
    private var handleEntities: [CarPart: Entity] = [:]
    private var wheelEntities: [WheelPosition: Entity] = [:]
    private var uniqueWheels: [Entity] = []
    private var lightEntities: [LightGroup: [Entity]] = [:]
    private var doorTilt: [CarPart: Float] = [:]
    private var sunroofRest: SIMD3<Float> = .zero
    private var sunroofOpen: SIMD3<Float> = .zero
    private var sunroofTilt: Float = 0
    private var windowRest: [CarPart: SIMD3<Float>] = [:]
    private var windowOpen: [CarPart: SIMD3<Float>] = [:]
    private var windowTilt: [CarPart: Float] = [:]
    private var handleTilt: [CarPart: Float] = [:]
    private var wheelRPM: Float = 4
    private var wheelCancellable: Cancellable?

    /// [Double] → SIMD3<Float>（逐元素构造，避免数组初始化歧义）
    private static func v3(_ a: [Double]) -> SIMD3<Float> {
        SIMD3<Float>(Float(a[0]), Float(a[1]), Float(a[2]))
    }

    /// 贴图资源 URL：先按裸名在 bundle 根查找，失败再回退到各贴图子目录
    /// （XcodeGen 打包时资源目录层级可能被扁平化，也可能被保留成子目录，两种都要兜住）。
    private static let textureSubdirectories = ["tex"]

    private static func textureURL(named texName: String) -> URL? {
        let base = (texName as NSString).deletingPathExtension
        let ext = (texName as NSString).pathExtension
        if let u = Bundle.main.url(forResource: base, withExtension: ext) { return u }
        for sub in textureSubdirectories {
            if let u = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: sub) {
                return u
            }
        }
        return nil
    }

    /// 分组名 → CarPart（门/尾门/天窗，用于触控点映射与部件注册）
    private static let partToCarPart: [String: CarPart] = [
        "doorFL": .doorFrontLeft, "doorFR": .doorFrontRight,
        "doorBL": .doorRearLeft, "doorBR": .doorRearRight,
        "trunk": .trunk, "sunroof": .sunroof
    ]
    private static let windowGroupToPart: [String: CarPart] = [
        "windowFL": .doorFrontLeft, "windowFR": .doorFrontRight,
        "windowBL": .doorRearLeft, "windowBR": .doorRearRight
    ]
    private static let handleGroupToPart: [String: CarPart] = [
        "handleFL": .doorFrontLeft, "handleFR": .doorFrontRight,
        "handleBL": .doorRearLeft, "handleBR": .doorRearRight
    ]

    // MARK: 初始化

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupARView()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupARView()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // 视口尺寸确定后重算取景距离：
        // 自动取景依赖视口宽高比，首帧 attach 时 bounds 可能还是 0，
        // 此处拿到真实尺寸再取景一次，保证整车完整入画。
        if hasModelBounds, bounds.width > 0, bounds.size != lastFramedSize {
            lastFramedSize = bounds.size
            applyOrbitCamera()
        }
    }

    private func setupARView() {
        backgroundColor = .clear
        arView = ARView(frame: .zero, cameraMode: .nonAR)
        arView.backgroundColor = .clear
        arView.environment.background = .color(.clear)
        addSubview(arView)
        arView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            arView.leadingAnchor.constraint(equalTo: leadingAnchor),
            arView.trailingAnchor.constraint(equalTo: trailingAnchor),
            arView.topAnchor.constraint(equalTo: topAnchor),
            arView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        // 新版 RealityKit（iOS 26 SDK）Scene 已移除 addChild，
        // 内容需挂到 AnchorEntity 后通过 scene.addAnchor 加入场景。
        let anchor = AnchorEntity()
        arView.scene.addAnchor(anchor)
        sceneAnchor = anchor
        setupCamera()
        setupLighting()
        setupStudioEnvironment()
    }

    private func setupCamera() {
        let camera = PerspectiveCamera()
        // FOV 42°（1.1.4）：比原来的 38° 略广，在「整车完整入画」的前提下
        // 让相机可以更近一些，车模在画面里占比更大、透视畸变更轻。
        camera.camera = PerspectiveCameraComponent(near: 0.05, far: 100, fieldOfViewInDegrees: 42)
        sceneAnchor?.addChild(camera)
        cameraEntity = camera
        applyOrbitCamera()
    }

    private func setupLighting() {
        // 主方向光：给车漆/金属件立体感（强度取中性，避免白车漆过曝）
        let key = DirectionalLight()
        key.light.intensity = 1600
        key.light.color = .white
        key.position = SIMD3<Float>(4, 6, 5)
        key.look(at: SIMD3<Float>(0, 0.3, 0), from: SIMD3<Float>(4, 6, 5), relativeTo: nil)
        sceneAnchor?.addChild(key)
        // 冷色补光压暗部
        let fill = DirectionalLight()
        fill.light.intensity = 500
        fill.light.color = UIColor(red: 0.82, green: 0.88, blue: 1.0, alpha: 1.0)
        fill.position = SIMD3<Float>(-5, 3, -4)
        fill.look(at: SIMD3<Float>(0, 0.3, 0), from: SIMD3<Float>(-5, 3, -4), relativeTo: nil)
        sceneAnchor?.addChild(fill)
        // 轮廓光：勾出车顶/肩线，避免车模在浅色卡片背景上"融掉"
        let rim = DirectionalLight()
        rim.light.intensity = 900
        rim.light.color = UIColor(red: 1.0, green: 0.96, blue: 0.90, alpha: 1.0)
        rim.position = SIMD3<Float>(0, 5, -6)
        rim.look(at: SIMD3<Float>(0, 0.4, 0), from: SIMD3<Float>(0, 5, -6), relativeTo: nil)
        sceneAnchor?.addChild(rim)
        // 地面反光（弱）：模拟展厅地面反射，避免车底死黑
        let bounce = DirectionalLight()
        bounce.light.intensity = 220
        bounce.light.color = UIColor(red: 0.92, green: 0.94, blue: 1.0, alpha: 1.0)
        bounce.position = SIMD3<Float>(0, -3, 2)
        bounce.look(at: SIMD3<Float>(0, 0.2, 0), from: SIMD3<Float>(0, -3, 2), relativeTo: nil)
        sceneAnchor?.addChild(bounce)
    }

    // MARK: 展厅环境光（IBL）

    /// 生成一张「摄影棚」等距柱状环境图（上亮下暗 + 顶部柔光箱），
    /// 交给 RealityKit 作为 IBL：车漆与镀铬件会出现真实的环境反射，
    /// 这是实车 3D 车模「好看」的关键（否则只有两盏平行光，金属面发黑发平）。
    private static func makeStudioEquirectangular() -> CGImage? {
        let width = 256, height = 128
        let cs = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            let v = Double(y) / Double(height - 1)      // 0 = 顶部
            for x in 0..<width {
                let u = Double(x) / Double(width - 1)
                // 上半部天空：由亮到中灰；下半部地面：偏暗冷灰
                let top: Double = 1.0
                let horizon: Double = 0.62
                let bottom: Double = 0.20
                let base: Double
                if v < 0.5 {
                    let t = v / 0.5
                    base = top + (horizon - top) * pow(t, 0.8)
                } else {
                    let t = (v - 0.5) / 0.5
                    base = horizon + (bottom - horizon) * t
                }
                // 顶部偏后方一块柔光箱（给车顶一条长高光）
                let boxU = abs(u - 0.5)
                let boxV = abs(v - 0.16)
                var boost = 0.0
                if boxU < 0.16 && boxV < 0.10 {
                    boost = (1.0 - boxU / 0.16) * (1.0 - boxV / 0.10) * 0.55
                }
                let val = min(1.0, base + boost)
                let i = (y * width + x) * 4
                pixels[i] = UInt8(val * 255)
                pixels[i + 1] = UInt8(val * 253)
                pixels[i + 2] = UInt8(min(1.0, val * 1.02) * 255)
                pixels[i + 3] = 255
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: cs,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true,
                       intent: .defaultIntent)
    }

    /// 是否具备可用的环境光（IBL）。
    /// EnvironmentResource 的代码生成入口仅 iOS 18+ 稳定可用；
    /// iOS 15–17 拿不到环境贴图，金属件必须降级处理，否则渲染成黑块。
    private static var hasImageBasedLight: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    private func setupStudioEnvironment() {
        guard let cg = Self.makeStudioEquirectangular() else { return }
        // EnvironmentResource 是 @MainActor 类型，放到主线程任务里生成并挂载。
        // 版本说明：
        //   · 老的静态 generate 接口已在新版 SDK 中被移除，不能再引用；
        //   · init(equirectangular:withName:) 仅 iOS 18+ 可用（本 App 部署目标 iOS 15）；
        //   · init(equirectangular:options:) 仅 iOS 27+ 可用。
        // 因此按可用性分支：iOS 18+ 走新初始化器拿到影棚 IBL；
        // iOS 15–17 无稳定代码生成 IBL 的 API，退化为「强化灯位 + 清漆层」方案
        //（见 setupLighting / makeMaterial），视觉上同样有影棚级高光。
        Task { @MainActor in
            if #available(iOS 18.0, *) {
                if let res = try? await EnvironmentResource(equirectangular: cg, withName: "studio") {
                    arView.environment.lighting.resource = res
                    // 适度提升 IBL 强度：让车漆/镀铬件出现清晰的环境反射高光
                    arView.environment.lighting.intensityExponent = 0.8
                }
            }
        }
    }

    // MARK: 轨道相机

    public func setOrbit(azimuth: Float? = nil, elevation: Float? = nil, radius: Float? = nil) {
        if let azimuth = azimuth { orbitAzimuth = azimuth }
        if let elevation = elevation { orbitElevation = min(max(elevation, 0.03), 1.15) }
        if let radius = radius {
            // 半径改为「相对自动取景距离的倍率」：自动取景负责保证整车不被裁切，
            // 用户捏合只在此基础上做放大/缩小，不会破坏取景约束。
            let base = fittedRadius(target: orbitTarget)
            userZoom = min(max(radius / max(base, 0.001), 0.45), 1.9)
        }
        applyOrbitCamera()
    }

    /// 用户手势缩放：传入倍率（>1 放大、<1 缩小），叠加在自动取景距离之上
    public func zoom(by factor: Float) {
        guard factor > 0.01, factor < 100 else { return }
        userZoom = min(max(userZoom / factor, 0.45), 1.9)
        applyOrbitCamera()
    }

    public func resetCamera() {
        userZoom = 1.0
        setOrbit(azimuth: Self.defaultAzimuth, elevation: Self.defaultElevation)
    }

    private func applyOrbitCamera() {
        guard let camera = cameraEntity else { return }
        let ce = cos(orbitElevation)
        let target = orbitTarget
        // 1.1.4 用户反馈「车模旋转时有一部分被遮挡」：
        // 固定相机距离在侧视（车长 3.876m 全部展开）时装不下整车，
        // 车头/车尾会被视口边缘裁掉。这里按当前旋转角度**动态计算**
        // 刚好能容纳整车的距离 —— 相当于「无边界取景」：
        // 无论转到哪个角度，整车都完整可见且尽量占满画面。
        let radius = fittedRadius(target: target) * userZoom
        orbitRadius = radius
        let pos = SIMD3<Float>(
            target.x + radius * ce * sin(orbitAzimuth),
            target.y + radius * sin(orbitElevation),
            target.z + radius * ce * cos(orbitAzimuth)
        )
        camera.look(at: target, from: pos, relativeTo: nil)
    }

    /// 计算「刚好容纳整车」的相机距离。
    ///
    /// 做法：把包围盒 8 个角点投影到相机的屏幕坐标系（相机 right / up 轴），
    /// 求出在该视角下所需的最小距离；再按视口宽高比（ARView 约 1.5:1，
    /// 水平视野远宽于垂直）取水平/垂直两个方向需求中的较大者。
    ///
    /// 垂直方向还做了「非对称预留」：舞台顶部有「重置视角 / 3D-2D」浮层按钮，
    /// 顶部留 28pt、底部留 6pt，避免车顶被浮层压住、车底被裁边。
    private func fittedRadius(target: SIMD3<Float>) -> Float {
        guard hasModelBounds else { return orbitRadius }
        let halfFov = Float(42) * .pi / 180 / 2      // 与 setupCamera 的 FOV 保持一致
        // RealityKit 的 fieldOfViewInDegrees 默认按「垂直」方向应用（CameraFieldOfViewOrientation.vertical），
        // 水平视野由视口宽高比推导：tanH = tanV * aspect
        let tanV = tan(halfFov)
        // 视口宽高比：优先用真实尺寸（3D 档舞台高 240pt，宽约屏宽-40pt）
        // 注意 bounds 是 CGFloat，需统一转成 Float 再参与浮点运算
        let w: Float = bounds.width > 0 ? Float(bounds.width) : 340
        let h: Float = bounds.height > 0 ? Float(bounds.height) : 240
        let aspect = max(0.6, min(3.0, w / h))
        let tanH = tanV * aspect
        // 上下非对称预留（换算成 NDC：顶部只允许用到 ndcTop，底部到 ndcBottom）
        let ndcTop = max(0.25, 1.0 - 2.0 * (28.0 / h))
        let ndcBottom = -max(0.25, 1.0 - 2.0 * (6.0 / h))

        // 相机基向量（look(at:from:) 的右/上轴）
        let ce = cos(orbitElevation)
        let dir = SIMD3<Float>(ce * sin(orbitAzimuth), sin(orbitElevation), ce * cos(orbitAzimuth))
        // forward = -dir；right = normalize(cross(forward, worldUp))；up = cross(right, forward)
        let forward = -dir
        let worldUp = SIMD3<Float>(0, 1, 0)
        var right = simd_cross(forward, worldUp)
        if simd_length(right) < 1e-5 { right = SIMD3<Float>(1, 0, 0) }
        right = simd_normalize(right)
        let up = simd_normalize(simd_cross(right, forward))

        // 精确解：相机在 target + R*dir 处，角点 p 的相机空间深度为
        //   depth = R - dot(p - target, dir)
        // 水平入画条件： |x| <= depth * tanH  →  R >= dot(rel,dir) + |x|/tanH
        // 垂直入画条件： y <= depth * tanV * ndcTop（上）/ -y <= depth * tanV * (-ndcBottom)（下）
        // 对 8 个角点取最大值即为所需最小距离。
        var need = 0.0 as Float
        for i in 0..<8 {
            let corner = SIMD3<Float>(
                (i & 1) == 0 ? modelBoundsMin.x : modelBoundsMax.x,
                (i & 2) == 0 ? modelBoundsMin.y : modelBoundsMax.y,
                (i & 4) == 0 ? modelBoundsMin.z : modelBoundsMax.z
            )
            let rel = corner - target
            let x = abs(simd_dot(rel, right))
            let y = simd_dot(rel, up)               // 上为正、下为负
            let along = simd_dot(rel, dir)          // 沿「target→相机」方向的分量
            // 该角点在垂直方向的可用视野比例（上方受顶部浮层限制，下方接近满幅）
            let vLimit = tanV * (y >= 0 ? ndcTop : -ndcBottom)
            // 该角点同时受水平/垂直两个约束，取二者较大者（Swift 的 max 只接受两个参数）
            need = max(need, along + max(x / tanH, abs(y) / vLimit))
        }
        // 余量系数 1.04：略大于「刚好容纳」的临界值，保证车头/车尾任何角度都不贴边、不被裁切。
        return max(1.2, need * 1.04)
    }

    // MARK: 模型加载（后台解析 → 主线程挂载）

    /// 在后台线程调用：解析 .rk.json/.rk.bin、构建全部实体与材质，返回已组装的车模。
    /// 不接触任何视图/场景状态，可在任意队列安全调用。
    /// - Parameter name: 资源名（不带扩展名，对应 EadoPlus2022.rk.json / .rk.bin）
    public static func buildCarModel(named name: String) -> RKCarModel? {
        // 只要求清单存在：几何文件由 manifest.geometryFile 指定，
        // 配色变体（如灰色逸动 EadoPlus2022Gray）复用同一份 .rk.bin，
        // 因此这里不能按 name 强制要求 "<name>.rk.bin" 存在（否则灰色款加载失败）。
        guard let jsonURL = Bundle.main.url(forResource: "\(name).rk", withExtension: "json") else {
            return nil
        }
        do {
            let jsonData = try Data(contentsOf: jsonURL)
            let manifest = try JSONDecoder().decode(RKManifest.self, from: jsonData)
            let geoName = manifest.geometryFile.isEmpty ? "\(name).rk.bin" : manifest.geometryFile
            guard let binURL = Bundle.main.url(forResource: (geoName as NSString).deletingPathExtension,
                                               withExtension: (geoName as NSString).pathExtension) else {
                return nil
            }
            let binData = try Data(contentsOf: binURL)
            return try buildFromManifest(manifest, binData: binData)
        } catch {
            return nil
        }
    }

    private static func buildFromManifest(_ manifest: RKManifest, binData: Data) throws -> RKCarModel {
        // 预加载贴图（按文件名缓存）。XcodeGen 通常会把 Resources 扁平化进 bundle 根，
        // 但为稳妥，先按裸名查找，失败再回退到 tex/ 子目录。
        var textures: [String: TextureResource] = [:]
        for mat in manifest.materials {
            if let texName = mat.texture, textures[texName] == nil {
                if let url = Self.textureURL(named: texName) {
                    textures[texName] = try? TextureResource.load(contentsOf: url)
                }
            }
        }

        let carRoot = Entity()
        carRoot.name = "carRoot"
        var groupEntities: [String: Entity] = [:]
        var partEntities: [CarPart: Entity] = [:]
        var windowEntities: [CarPart: Entity] = [:]
        var handleEntities: [CarPart: Entity] = [:]
        var wheelEntities: [WheelPosition: Entity] = [:]
        var lightEntities: [LightGroup: [Entity]] = [:]
        var doorTilt: [CarPart: Float] = [:]
        var windowRest: [CarPart: SIMD3<Float>] = [:]
        var windowOpen: [CarPart: SIMD3<Float>] = [:]
        var windowTilt: [CarPart: Float] = [:]
        var handleTilt: [CarPart: Float] = [:]

        func groupEntity(_ name: String) -> Entity {
            if let e = groupEntities[name] { return e }
            let g = manifest.groups[name]!
            let e = Entity()
            e.name = name
            if let parent = g.parent {
                let pe = groupEntity(parent)          // 递归确保父组已创建
                // 子组（车窗/把手）顶点相对「自身组 position」烘焙，
                // 实体须放在该偏移上，否则玻璃/把手会错位到车门板上
                e.position = Self.v3(g.position)
                pe.addChild(e)
            } else {
                e.position = Self.v3(g.position)
                carRoot.addChild(e)
            }
            groupEntities[name] = e
            return e
        }

        // glb 自带的假地面阴影面片（C211_Tex_Shadow，tex_4 半透明贴图）在
        // RealityKit 下渲染成发白面片，且与本 App 纯净卡片背景不搭：
        // 直接不渲染，车模悬浮于干净背景上。
        let skippedMaterials: Set<String> = ["C211_Tex_Shadow"]
        for part in manifest.parts {
            if skippedMaterials.contains(manifest.materials[part.material].name) { continue }
            let ge = groupEntity(part.group)
            let model = try buildModelEntity(part: part, manifest: manifest, data: binData, textures: textures)
            ge.addChild(model)

            if let cp = partToCarPart[part.group] {
                partEntities[cp] = ge
            }
            if let cp = windowGroupToPart[part.group] {
                windowEntities[cp] = ge
            }
            if let cp = handleGroupToPart[part.group] {
                handleEntities[cp] = ge
            }
            if part.isLight {
                // 所有自发光灯件默认隐藏，只有归入「可点亮分组」的才在对应状态下显示。
                // 未分组件（如门迎宾灯 Light_*_LOn_Door_*、DRL）默认不显示，
                // 否则会在车身两侧常驻两块多余灯光（1.1.4 实机反馈）。
                model.isEnabled = false
                if let lg = lightGroupFor(name: part.name) {
                    lightEntities[lg, default: []].append(model)
                }
            }
        }

        // 世界包围盒（自动取景用）：顶点坐标 + 所属组（含父链）的 position 偏移
        // 组层级：车门 / 尾门 / 天车 / 车轮 / 车窗 / 把手；车窗与把手是车门的子节点，
        // 其实体挂在父组下，因此世界偏移需要沿 parent 链累加。
        func groupWorldOffset(_ name: String) -> SIMD3<Float> {
            var sum = SIMD3<Float>(repeating: 0)
            var cur: String? = name
            var guardCount = 0
            while let g = cur, guardCount < 8 {
                guardCount += 1
                guard let def = manifest.groups[g] else { break }
                let p = def.position
                sum += SIMD3<Float>(Float(p[0]), Float(p[1]), Float(p[2]))
                cur = def.parent
            }
            return sum
        }
        var boundsMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var boundsMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        for part in manifest.parts {
            if skippedMaterials.contains(manifest.materials[part.material].name) { continue }
            let off = groupWorldOffset(part.group)
            let vc = part.vertexCount
            let base = part.positionOffset
            for i in 0..<vc {
                let o = base + i * 12
                guard o + 12 <= binData.count else { break }
                let x = Float(bitPattern: UInt32(binData[o]) | (UInt32(binData[o+1]) << 8)
                    | (UInt32(binData[o+2]) << 16) | (UInt32(binData[o+3]) << 24))
                let y = Float(bitPattern: UInt32(binData[o+4]) | (UInt32(binData[o+5]) << 8)
                    | (UInt32(binData[o+6]) << 16) | (UInt32(binData[o+7]) << 24))
                let z = Float(bitPattern: UInt32(binData[o+8]) | (UInt32(binData[o+9]) << 8)
                    | (UInt32(binData[o+10]) << 16) | (UInt32(binData[o+11]) << 24))
                let wx = x + off.x, wy = y + off.y, wz = z + off.z
                boundsMin.x = min(boundsMin.x, wx); boundsMax.x = max(boundsMax.x, wx)
                boundsMin.y = min(boundsMin.y, wy); boundsMax.y = max(boundsMax.y, wy)
                boundsMin.z = min(boundsMin.z, wz); boundsMax.z = max(boundsMax.z, wz)
            }
        }

        // 动画参数
        for (gname, g) in manifest.groups {
            if let cp = partToCarPart[gname], cp != .trunk, cp != .sunroof {
                doorTilt[cp] = Float(g.openTiltDeg ?? 0) * (.pi / 180)
            }
        }
        if let g = manifest.groups["trunk"] {
            doorTilt[.trunk] = Float(g.openTiltDeg ?? 0) * (.pi / 180)
        }
        var sunroofRest: SIMD3<Float> = .zero
        var sunroofOpen: SIMD3<Float> = .zero
        var sunroofTilt: Float = 0
        if let g = manifest.groups["sunroof"] {
            sunroofRest = Self.v3(g.position)
            sunroofOpen = Self.v3(g.openPosition ?? g.position)
            sunroofTilt = Float(g.openTiltDeg ?? 0) * (.pi / 180)
        }
        for (gname, cp) in windowGroupToPart {
            if let g = manifest.groups[gname] {
                windowRest[cp] = Self.v3(g.position)
                windowOpen[cp] = Self.v3(g.openPosition ?? g.position)
                windowTilt[cp] = Float(g.openTiltDeg ?? 0) * (.pi / 180)
            }
        }
        for (gname, cp) in handleGroupToPart {
            if let g = manifest.groups[gname] {
                handleTilt[cp] = Float(g.openTiltDeg ?? 0) * (.pi / 180)
            }
        }
        for (gname, wp) in [("wheelFL", WheelPosition.frontLeft), ("wheelFR", WheelPosition.frontRight),
                            ("wheelBL", WheelPosition.rearLeft), ("wheelBR", WheelPosition.rearRight),
                            ("wheelB", WheelPosition.rearLeft), ("wheelB", WheelPosition.rearRight)] {
            if let ge = groupEntities[gname] {
                wheelEntities[wp] = ge
            }
        }
        var seenWheels = Set<ObjectIdentifier>()
        var uniqueWheels: [Entity] = []
        for w in wheelEntities.values {
            let id = ObjectIdentifier(w)
            if seenWheels.insert(id).inserted { uniqueWheels.append(w) }
        }

        return RKCarModel(root: carRoot, partEntities: partEntities, windowEntities: windowEntities,
                          handleEntities: handleEntities, wheelEntities: wheelEntities,
                          uniqueWheels: uniqueWheels, lightEntities: lightEntities,
                          doorTilt: doorTilt, sunroofRest: sunroofRest, sunroofOpen: sunroofOpen,
                          sunroofTilt: sunroofTilt, windowRest: windowRest, windowOpen: windowOpen,
                          windowTilt: windowTilt, handleTilt: handleTilt,
                          boundsMin: boundsMin, boundsMax: boundsMax)
    }

    private static func buildModelEntity(part: RKPartDef, manifest: RKManifest, data: Data,
                                         textures: [String: TextureResource]) throws -> ModelEntity {
        let vc = part.vertexCount
        let ic = part.indexCount

        let posFloats = data.subdata(in: part.positionOffset..<(part.positionOffset + vc * 3 * 4))
            .withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(vc)
        for i in 0..<vc { positions.append(SIMD3<Float>(posFloats[i*3], posFloats[i*3+1], posFloats[i*3+2])) }

        var normals: [SIMD3<Float>]?
        if let no = part.normalOffset {
            let nFloats = data.subdata(in: no..<(no + vc * 3 * 4)).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            normals = []
            normals!.reserveCapacity(vc)
            for i in 0..<vc { normals!.append(SIMD3<Float>(nFloats[i*3], nFloats[i*3+1], nFloats[i*3+2])) }
        }
        var uvs: [SIMD2<Float>]?
        if let uo = part.uvOffset {
            let uFloats = data.subdata(in: uo..<(uo + vc * 2 * 4)).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            uvs = []
            uvs!.reserveCapacity(vc)
            for i in 0..<vc { uvs!.append(SIMD2<Float>(uFloats[i*2], uFloats[i*2+1])) }
        }
        let indices = data.subdata(in: part.indexOffset..<(part.indexOffset + ic * 4))
            .withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }

        var descriptor = MeshDescriptor(name: part.name)
        descriptor.positions = MeshBuffers.Positions(positions)
        if let normals { descriptor.normals = MeshBuffers.Normals(normals) }
        if let uvs { descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs) }
        descriptor.primitives = .triangles(indices)
        descriptor.materials = .allFaces(0)
        let mesh = try MeshResource.generate(from: [descriptor])

        let mat = makeMaterial(manifest.materials[part.material], textures: textures)
        return ModelEntity(mesh: mesh, materials: [mat])
    }

    private static func makeMaterial(_ def: RKMaterialDef, textures: [String: TextureResource]) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        let c = def.baseColorSRGB
        let lowerName = def.name.lowercased()
        let isGlass = lowerName.contains("glass") || lowerName.contains("window")
        // 无贴图的透明件（车窗玻璃 / 灯罩玻璃）给固定半透明，呈现玻璃质感
        // 玻璃件用更高不透明度（0.72），压暗后的基色才能读成「深色玻璃」而不是「透明片」
        var baseAlpha: CGFloat = 1
        if def.blend && def.texture == nil {
            baseAlpha = isGlass ? 0.72 : 0.4
        } else if c.count > 3 {
            baseAlpha = c[3]
        }
        let tint = UIColor(red: CGFloat(c[0]), green: CGFloat(c[1]), blue: CGFloat(c[2]),
                          alpha: baseAlpha)
        m.baseColor = .init(tint: tint)
        m.metallic = .init(floatLiteral: Float(def.metallic))
        m.roughness = .init(floatLiteral: Float(def.roughness))
        // 金属度钳制：无环境光（IBL）时，metallic≈1 的金属件没有可反射的光源，
        // 会直接渲染成黑块（轮毂、饰条、logo 全部发黑）。
        // iOS 18+ 通过 EnvironmentResource 挂载程序化影棚环境图后无需降级；
        // iOS 15–17 无 IBL 时把金属度压到 0.25 并同步提高粗糙度，
        // 让金属件退回「漫反射高光」表现，不再出现黑块。
        if !Self.hasImageBasedLight, def.metallic > 0.3 {
            m.metallic = .init(floatLiteral: 0.25)
            m.roughness = .init(floatLiteral: min(1.0, Float(def.roughness) * 1.4 + 0.12))
        }
        // 车漆清漆层（clearcoat）：官方展厅模的实车质感来自这一层，
        // 没有它金属/车漆面会显得「塑料」，加一层薄清漆立刻有影棚级高光。
        // 覆盖范围：车漆主件（carpaint / car_paint）、官方模的 CP 车漆层、
        // 以及 UNI-K 的 black_ref 车门大面（与车漆同色的覆盖件），
        // 否则同一台车上会出现「车身发亮、门板发塑料」的不一致。
        let isPaintLike = lowerName.contains("carpaint")
            || lowerName.contains("car_paint")
            || lowerName.contains("cp_m")
            || lowerName.contains("black_ref")
        if isPaintLike {
            m.clearcoat = 0.9
            m.clearcoatRoughness = 0.06
        }
        if let e = def.emissiveSRGB, !e.isEmpty {
            let ec = UIColor(red: CGFloat(e[0]), green: CGFloat(e[1]), blue: CGFloat(e[2]),
                            alpha: CGFloat(e.count > 3 ? e[3] : 1))
            m.emissiveColor = .init(color: ec)
            m.emissiveIntensity = 1.6
        }
        if let tn = def.texture, let tex = textures[tn] {
            m.baseColor.texture = .init(tex)
        }
        // 玻璃/灯罩等半透明件：无论是否带贴图，都启用透明混合，
        // 否则 baseColor 的 alpha 会被默认不透明混合忽略，玻璃变成实心。
        if def.blend {
            m.blending = .transparent(opacity: 1.0)
        }
        if def.doubleSided { m.faceCulling = .none }
        return m
    }

    private static func lightGroupFor(name: String) -> LightGroup? {
        // 1.1.4 实机反馈：逸动车身两侧各有一块多余灯光 —— 来源是门迎宾灯
        // （Light_L_LOn_Door_FL / Light_R_LOn_Door_FR）。官方展厅模的迎宾灯只在
        // 解锁瞬间闪一下，常亮非常违和，因此这里**不再**给 doorLight 组任何灯件，
        // 车门/门把手的状态由开合动画与弹起表现。
        // 仅主大灯进入 headlight 组；DRL / 左右示宽(LOn_Ext) 也不点亮，
        // 否则车身两侧会出现多余光带。
        if name.contains("HL_LOn") { return .headlight }
        if name.contains("DRL_LOn") { return .headlight }   // 日行灯随大灯一起点亮
        if name.contains("TL_LOn") { return .taillight }
        if name.contains("BL_LOn") { return .brake }
        return nil
    }

    /// 主线程挂载已构建的车模，索引部件、应用初始状态。
    @discardableResult
    public func attach(_ build: RKCarModel) -> Bool {
        clearModel()
        carRoot = build.root
        partEntities = build.partEntities
        windowEntities = build.windowEntities
        handleEntities = build.handleEntities
        wheelEntities = build.wheelEntities
        uniqueWheels = build.uniqueWheels
        lightEntities = build.lightEntities
        doorTilt = build.doorTilt
        sunroofRest = build.sunroofRest
        sunroofOpen = build.sunroofOpen
        sunroofTilt = build.sunroofTilt
        windowRest = build.windowRest
        windowOpen = build.windowOpen
        windowTilt = build.windowTilt
        handleTilt = build.handleTilt
        sceneAnchor?.addChild(build.root)
        availableParts = Set(partEntities.keys)
        hasWindows = !windowEntities.isEmpty
        hasLights = !lightEntities.isEmpty
        hasWheels = !uniqueWheels.isEmpty
        applyLockState(animated: false)
        applyLightState(animated: false)
        // 记录包围盒并把注视点移到车模中心，供自动取景使用
        modelBoundsMin = build.boundsMin
        modelBoundsMax = build.boundsMax
        hasModelBounds = true
        orbitTarget = (build.boundsMin + build.boundsMax) / 2
        applyOrbitCamera()
        return true
    }

    public func clearModel() {
        partEntities.removeAll()
        windowEntities.removeAll()
        handleEntities.removeAll()
        wheelEntities.removeAll()
        uniqueWheels.removeAll()
        lightEntities.removeAll()
        doorTilt.removeAll()
        windowRest.removeAll(); windowOpen.removeAll(); windowTilt.removeAll(); handleTilt.removeAll()
        partAngles.removeAll()
        carRoot?.removeFromParent()
        carRoot = nil
        hasModelBounds = false
        userZoom = 1.0
        stopWheels()
        wheelCancellable?.cancel()
        wheelCancellable = nil
    }

    // MARK: 部件控制

    public func setPart(_ part: CarPart, open: Bool, duration: TimeInterval = 0.35) {
        if part == .sunroof {
            setSunroof(open: open, duration: duration)
            return
        }
        guard let entity = partEntities[part], let tiltDeg = doorTilt[part] else { return }
        let axis: SIMD3<Float> = (part == .trunk) ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        let angle = open ? Float(tiltDeg) : 0
        animate(entity: entity, axis: axis, angle: angle, duration: duration)
        partAngles[part] = abs(angle)
        if lowerWindowsWithDoors, let win = windowEntities[part] {
            setWindowEntity(win, part: part, open: open, duration: duration)
        }
    }

    /// 真实车况驱动的部件开合：与手动预览不同，车窗升降**不**跟随车门，
    /// 而是完全由车窗状态字段决定（解锁一扇门不代表车窗降下）。
    public func setPartFromStatus(_ part: CarPart, open: Bool, duration: TimeInterval = 0.35) {
        let saved = lowerWindowsWithDoors
        lowerWindowsWithDoors = false
        setPart(part, open: open, duration: duration)
        lowerWindowsWithDoors = saved
    }

    private func animate(entity: Entity, axis: SIMD3<Float>, angle: Float, duration: Double) {
        var t = entity.transform
        t.rotation = simd_quatf(angle: angle, axis: axis)
        entity.move(to: t, relativeTo: entity.parent, duration: duration, timingFunction: .easeInOut)
    }

    public func setWindow(_ part: CarPart, open: Bool, duration: TimeInterval = 0.35) {
        guard let win = windowEntities[part] else { return }
        setWindowEntity(win, part: part, open: open, duration: duration)
    }

    private func setWindowEntity(_ entity: Entity, part: CarPart, open: Bool, duration: Double) {
        guard let rest = windowRest[part], let openPos = windowOpen[part], let tiltDeg = windowTilt[part] else { return }
        // 实体静止位 = 组 position（顶点相对其烘焙）；开窗平移到 openPosition（同为父门组局部坐标）
        let target = open ? openPos : rest
        let tilt = open ? Float(tiltDeg) : 0
        var t = Transform(scale: entity.transform.scale,
                          rotation: simd_quatf(angle: tilt, axis: SIMD3<Float>(0, 0, 1)),
                          translation: target)
        entity.move(to: t, relativeTo: entity.parent, duration: duration, timingFunction: .easeInOut)
    }

    private func setSunroof(open: Bool, duration: Double) {
        guard let entity = partEntities[.sunroof] else { return }
        let target = open ? sunroofOpen : sunroofRest
        let tilt = open ? sunroofTilt : 0
        var t = Transform(scale: entity.transform.scale,
                          rotation: simd_quatf(angle: tilt, axis: SIMD3<Float>(1, 0, 0)),
                          translation: target)
        entity.move(to: t, relativeTo: entity.parent, duration: duration, timingFunction: .easeInOut)
        partAngles[.sunroof] = abs(tilt)
    }

    public func setDoorOpen(_ open: Bool) {
        setPart(.doorFrontLeft, open: open); setPart(.doorFrontRight, open: open)
        setPart(.doorRearLeft, open: open); setPart(.doorRearRight, open: open)
    }
    public func setTrunkOpen(_ open: Bool) { setPart(.trunk, open: open) }
    public func setHoodOpen(_ open: Bool) { setPart(.hood, open: open) }
    public func setSunroofOpen(_ open: Bool) { setPart(.sunroof, open: open) }
    public func setChargePortOpen(_ open: Bool) { setPart(.chargePort, open: open) }

    // MARK: 门把手（解锁弹出）

    public func setHandlesOpen(_ open: Bool, duration: TimeInterval = 0.3) {
        for (part, entity) in handleEntities {
            guard let tiltDeg = handleTilt[part] else { continue }
            let tilt = open ? Float(tiltDeg) : 0
            animate(entity: entity, axis: SIMD3<Float>(0, 1, 0), angle: tilt, duration: duration)
        }
    }

    public func setUnlocked(_ unlocked: Bool, animated: Bool = true) {
        isUnlocked = unlocked
        applyLockState(animated: animated)
    }

    private func applyLockState(animated: Bool) {
        setHandlesOpen(isUnlocked, duration: animated ? 0.3 : 0.001)
    }

    // MARK: 车轮

    public func startWheels(rpm: Float = 4) {
        guard !isWheelsSpinning, !uniqueWheels.isEmpty else { return }
        isWheelsSpinning = true
        wheelRPM = rpm
        if wheelCancellable == nil {
            wheelCancellable = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] ev in
                self?.spinStep(delta: ev.deltaTime)
            }
        }
    }

    public func stopWheels() {
        isWheelsSpinning = false
    }

    private func spinStep(delta: Double) {
        guard isWheelsSpinning else { return }
        let angle = Float(delta) * wheelRPM * (2 * Float.pi / 60)
        let q = simd_quatf(angle: angle, axis: SIMD3<Float>(1, 0, 0))
        for e in uniqueWheels {
            e.setOrientation(simd_mul(q, e.orientation), relativeTo: e.parent ?? e)
        }
    }

    // MARK: 灯光控制

    public func setLights(headlight: Bool, taillight: Bool = false, brake: Bool = false) {
        lightEntities[.headlight]?.forEach { $0.isEnabled = headlight }
        lightEntities[.taillight]?.forEach { $0.isEnabled = (taillight || brake) }
        lightEntities[.brake]?.forEach { $0.isEnabled = brake }
        applyDoorLights(on: isUnlocked)
    }

    public func setLights(brakeOn: Bool) {
        setLights(headlight: false, taillight: brakeOn, brake: brakeOn)
    }

    private func applyLightState(animated: Bool) {
        setLights(headlight: false, taillight: false, brake: false)
    }

    private func applyDoorLights(on: Bool) {
        lightEntities[.doorLight]?.forEach { $0.isEnabled = on }
    }

    // MARK: 触控点控车

    /// 由屏幕坐标命中部件：用 ARView.entity(at:) 取最上层实体，向上回溯到所属功能分组。
    public func part(at point: CGPoint) -> CarPart? {
        guard let entity = arView.entity(at: point) else { return nil }
        var current: Entity? = entity
        while let e = current {
            if let p = Self.partToCarPart[e.name] { return p }
            current = e.parent
        }
        return nil
    }

    // MARK: 可访问性

    public override func didMoveToWindow() {
        super.didMoveToWindow()
        isAccessibilityElement = true
        accessibilityLabel = "车辆 3D 模型"
        accessibilityHint = "双指旋转或缩放查看车身；控制按钮可开关车门与后备箱"
        accessibilityTraits = .none
    }
}
