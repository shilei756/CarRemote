//
//  Car3DView.swift
//  长安控车 — 3D 车模组件（SceneKit）
//
//  适配车型：逸动PLUS 2022（内部代号 C211，官方 3D 车模，来自长安智慧云控 App 安装包）
//  同时兼容其他长安车型（CS75PLUS/UNI-V/UNI-K/UNI-T/CS55PLUS 等，节点名模糊匹配）。
//
//  功能：
//    - 加载 glb（iOS 15+ SceneKit 原生解析，零转换）或 COLLADA dae 车模
//    - 四门开/关（官方 75° 铰链旋转，绕节点局部 Y 轴，枢轴=节点原点）
//    - 后备箱开/关（官方 70° 绕局部 X 轴）
//    - 天窗开/关（官方后滑 51.6cm + 7.1° 翻转）
//    - 四门车窗随车门升降（官方下行动画，含 3° 微倾）
//    - 门把手弹出/收回（官方 10° 翻转，解锁时联动）
//    - 灯光控制：前灯/DRL/示宽/尾灯/刹车灯（官方 LOn 自发光网格显隐）
//    - 车轮持续转动（前轮 FR/FL 独立节点，后轮 B 为左右镜像单节点）
//    - 轨道相机：滑动旋转 / 捏合缩放 / 重置视角（由外层 SwiftUI 手势驱动，
//      不启用 allowsCameraControl，避免与仪表盘 ScrollView 滚动手势冲突）
//
//  用法（UIKit / UIViewRepresentable）：
//    let carView = Car3DView(frame: .zero)
//    let ok = carView.loadModel(named: "EadoPlus2022")   // 不带扩展名，false 时调用方兜底
//    carView.setPart(.doorFrontLeft, open: true)
//    carView.setLights(headlight: true, taillight: true, brake: false)
//
//  用法（SwiftUI）：
//    struct Car3DRepresentable: UIViewRepresentable {
//        func makeUIView(context: Context) -> Car3DView { Car3DView() }
//        func updateUIView(_ v: Car3DView, context: Context) { }
//    }
//
//  官方动画参数来源（智慧云控 C211.glb 内置 14 个动画剪辑，已逐帧解码）：
//    DoorOpen_*    : 1.33s，四门绕各自节点局部 Y 轴 ±75.0°（左门 -Y，右门 +Y）
//    LuggageDoorOpen: 1.50s，尾门绕局部 X 轴 +70.0°
//    WindowOpen_*  : 0.67s，车窗下沉 9.3~9.6cm 并外倾 2.97°（BL/FL 绕 -Z，BR/FR 绕 +Z）
//    WindowOpen_T  : 2.00s，天窗后滑 51.56cm 并绕 -X 翻转 7.11°
//    HandleOpen_*  : 1.00s，门把手绕局部 Y 轴 ±10.01°（左 -Y，右 +Y）
//
//  光照说明（吸取 1.0.7 白车过曝教训）：
//    - 中性环境光（强度 0.6）+ 主方向光（0.9）+ 冷色补光（0.25），
//      白车漆不会过曝，暗部不死黑；车漆金属质感由 PBR 贴图本身提供。
//

import SceneKit

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

    /// 逸动PLUS 2022（C211）官方节点名——精确匹配优先
    var c211Node: String? {
        switch self {
        case .doorFrontLeft:  return "Door_FL_P"
        case .doorFrontRight: return "Door_FR_P"
        case .doorRearLeft:   return "Door_BL_P"
        case .doorRearRight:  return "Door_BR_P"
        case .trunk:          return "LuggageDoor_P"
        case .sunroof:        return "Window_T_P"
        case .hood:           return nil   // C211 机盖为非独立网格，无开合动画
        case .chargePort:     return nil   // C211 为纯燃油车，无充电口
        }
    }

    /// C211 对应车窗节点（车门子节点，官方随车门联动下沉）
    var c211WindowNode: String? {
        switch self {
        case .doorFrontLeft:  return "Window_FL_P"
        case .doorFrontRight: return "Window_FR_P"
        case .doorRearLeft:   return "Window_BL_P"
        case .doorRearRight:  return "Window_BR_P"
        default:              return nil
        }
    }

    /// C211 门把手节点（解锁时弹出）
    var c211HandleNode: String? {
        switch self {
        case .doorFrontLeft:  return "Handle_FL_P"
        case .doorFrontRight: return "Handle_FR_P"
        case .doorRearLeft:   return "Handle_BL_P"
        case .doorRearRight:  return "Handle_BR_P"
        default:              return nil
        }
    }

    /// 其他车型的节点名模糊匹配规则（大小写不敏感）
    var patterns: [String] {
        switch self {
        case .doorFrontLeft:  return ["door_fl", "doorlf", "doorfrontleft", "leftfrontdoor", "lf", "左前"]
        case .doorFrontRight: return ["door_fr", "doorrf", "doorfrontright", "rightfrontdoor", "rf", "右前"]
        case .doorRearLeft:   return ["door_bl", "doorlb", "doorrearleft", "leftbackdoor", "lb", "左后"]
        case .doorRearRight:  return ["door_br", "doorrb", "doorrearright", "rightbackdoor", "rb", "右后"]
        case .trunk:          return ["luggagedoor", "trunk", "boot", "tailgate", "houbeixiang", "后备"]
        case .hood:           return ["enginedoor", "hood", "bonnet", "enginecover", "机盖"]
        case .sunroof:        return ["window_t", "sunroof", "tianchuang", "天窗"]
        case .chargePort:     return ["charge", "charging", "chongdian", "充电"]
        }
    }

    /// 是否位于车身左侧（C211 坐标系：+X 为左，与官方动画符号对应）
    var isLeftSide: Bool {
        switch self {
        case .doorFrontLeft, .doorRearLeft: return true
        default: return false
        }
    }
}

public enum WheelPosition: String, CaseIterable {
    case frontLeft, frontRight, rearLeft, rearRight
}

// MARK: - 车模视图

public final class Car3DView: SCNView {

    // MARK: 公开状态

    /// 各部件当前开合角度（弧度），0 = 关闭
    public private(set) var partAngles: [CarPart: Float] = [:]

    /// 车轮是否转动（模拟行驶）
    public private(set) var isWheelsSpinning = false

    /// 车门开启时是否联动降下车窗（默认 true，还原真实车辆与官方 App 行为）
    public var lowerWindowsWithDoors = true

    /// 当前锁状态（解锁时门把手保持弹出）
    public private(set) var isUnlocked = true

    // MARK: 私有

    private var carRoot: SCNNode?
    private var partNodes: [CarPart: SCNNode] = [:]
    private var windowNodes: [CarPart: SCNNode] = [:]
    private var handleNodes: [CarPart: SCNNode] = [:]
    private var wheelNodes: [WheelPosition: SCNNode] = [:]

    /// 灯光分组（LOn 自发光网格，默认隐藏，按状态显隐）
    private var lightGroups: [LightGroup: [SCNNode]] = [:]

    /// 记录各部件的关闭位（局部坐标），用于回落动画
    private var partRestPositions: [CarPart: SCNVector3] = [:]

    /// 记录各车窗/天窗的关闭位（局部坐标），用于回落动画
    private var windowRestPositions: [CarPart: SCNVector3] = [:]

    // MARK: 初始化

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupScene()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupScene()
    }

    private func setupScene() {
        scene = SCNScene()
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        isJitteringEnabled = true

        scene?.background.contents = nil

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.color = UIColor(white: 0.72, alpha: 1.0)   // 中性环境光，不提亮车漆
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene?.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .directional
        key.color = UIColor(white: 1.0, alpha: 1.0)
        key.intensity = 900                              // lx 单位，避免 >1500 造成白色车漆过曝
        key.castsShadow = true
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(3, 5, 4)
        keyNode.eulerAngles = SCNVector3(-Float.pi / 3, 0, -Float.pi / 4)
        scene?.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .directional
        fill.color = UIColor(red: 0.82, green: 0.88, blue: 1.0, alpha: 1.0) // 冷补光压暗部
        fill.intensity = 250
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(-4, 2, -3)
        scene?.rootNode.addChildNode(fillNode)

        // 默认机位：侧前 45°（轨道相机，与引力域车模默认视角一致）
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.fieldOfView = 38
        scene?.rootNode.addChildNode(cameraNode)
        pointOfView = cameraNode
        // 不用 allowsCameraControl：其内置手势会与仪表盘 ScrollView 的滚动抢手势，
        // 改为由外层 SwiftUI 提供「横向滑动旋转 / 捏合缩放」手势（见 CarModelStage.swift）。
        allowsCameraControl = false
        applyOrbitCamera()
    }

    // MARK: 轨道相机（滑动旋转 / 捏合缩放）

    /// 轨道方位角（弧度；0 = 车头正对屏幕右前方，增大 = 车身左转）
    public private(set) var orbitAzimuth: Float = Car3DView.defaultAzimuth
    /// 轨道仰角（弧度，钳制 0.03~1.15，防止钻到车底/正顶）
    public private(set) var orbitElevation: Float = Car3DView.defaultElevation
    /// 轨道半径（场景单位，钳制 3.6~10）
    public private(set) var orbitRadius: Float = Car3DView.defaultRadius
    /// 轨道注视点（车身中部，归一化后车高约 0.72）
    public private(set) var orbitTarget = SCNVector3(0, 0.36, 0)

    private static let defaultAzimuth: Float = 0.7383      // ≈ 42.3°，侧前 45°
    private static let defaultElevation: Float = 0.2514    // ≈ 14.4°，略微俯视
    private static let defaultRadius: Float = 6.2

    /// 设置轨道参数（nil = 保持当前值）。钳制在合理区间内。
    public func setOrbit(azimuth: Float? = nil, elevation: Float? = nil, radius: Float? = nil) {
        if let azimuth = azimuth { orbitAzimuth = azimuth }
        if let elevation = elevation { orbitElevation = min(max(elevation, 0.03), 1.15) }
        if let radius = radius { orbitRadius = min(max(radius, 3.6), 10) }
        applyOrbitCamera()
    }

    /// 重置视角到默认侧前 45°
    public func resetCamera() {
        setOrbit(azimuth: Self.defaultAzimuth, elevation: Self.defaultElevation, radius: Self.defaultRadius)
    }

    private func applyOrbitCamera() {
        guard let camera = pointOfView else { return }
        let ce = cos(orbitElevation)
        let x = orbitTarget.x + orbitRadius * ce * sin(orbitAzimuth)
        let y = orbitTarget.y + orbitRadius * sin(orbitElevation)
        let z = orbitTarget.z + orbitRadius * ce * cos(orbitAzimuth)
        camera.position = SCNVector3(x, y, z)
        camera.look(at: orbitTarget)
    }

    // MARK: 模型加载

    /// 加载车模。按 glb → dae 顺序自动匹配（Bundle 内资源）。
    /// - Parameter name: 不带扩展名的资源名
    /// - Returns: 是否加载成功；false 时调用方应兜底（如退回 2D 车图）
    @discardableResult
    public func loadModel(named name: String) -> Bool {
        guard let scene = Self.loadScene(named: name) else { return false }
        return attachScene(scene)
    }

    /// 后台线程解析模型文件（唯一耗时步骤：glb 解析 + 贴图解码）。
    /// 只创建独立的 SCNScene，不接触任何视图/场景状态，可在任意队列安全调用。
    /// - Parameter name: 不带扩展名的资源名
    /// - Returns: 解析出的场景；文件不存在或解析失败返回 nil
    public static func loadScene(named name: String) -> SCNScene? {
        // 1) iOS 15+ 直接解析 glTF/glb（零转换）
        if #available(iOS 15.0, *) {
            for ext in ["glb", "gltf"] {
                if let url = Bundle.main.url(forResource: name, withExtension: ext) {
                    // SCNScene(url:) 是 SceneKit 官方模型加载入口：内部经 ModelIO 解析 glb，
                    // 完整保留节点名 / 层级 / 变换 / 几何体 / PBR 材质，并自动加载内嵌纹理。
                    // 不走 MDLAsset 手动建树：iOS 26 SDK 起 SCNNode(mdlObject:) 等
                    // ModelIO→SceneKit 桥接触发器在 Swift 接口已不可见（CI 编译实证）。
                    return try? SCNScene(url: url, options: nil)
                }
            }
        }
        // 2) 兜底：COLLADA（iOS 全版本）
        if let url = Bundle.main.url(forResource: name, withExtension: "dae") {
            return try? SCNScene(url: url, options: nil)
        }
        return nil
    }

    /// 主线程挂载已解析的场景：归一化 → 索引部件 → 应用初始状态。
    /// - Parameter loaded: loadScene(named:) 的返回值
    /// - Returns: 是否挂载成功
    @discardableResult
    public func attachScene(_ loaded: SCNScene) -> Bool {
        clearModel()

        let root = loaded.rootNode
        normalize(root)                 // 居中 + 缩放到统一尺寸
        scene?.rootNode.addChildNode(root)
        carRoot = root

        indexParts(in: root)
        indexWindows(in: root)
        indexHandles(in: root)
        indexWheels(in: root)
        indexLights(in: root)

        // 初始状态：解锁（把手弹出）、灯光全关
        applyLockState(animated: false)
        applyLightState(animated: false)
        return true
    }

    public func clearModel() {
        partNodes.removeAll()
        windowNodes.removeAll()
        handleNodes.removeAll()
        wheelNodes.removeAll()
        partRestPositions.removeAll()
        windowRestPositions.removeAll()
        lightGroups.removeAll()
        partAngles.removeAll()
        carRoot?.removeFromParentNode()
        carRoot = nil
        stopWheels()
    }

    /// 居中、统一尺度（车长 ≈ 2.2 场景单位），并关闭导入的相机。
    /// 注意：C211 的前灯"点亮"网格（Light_HL_LOn_Ext）带 4 米长的光束几何体，
    /// 地面阴影（Shadow）也会放大包围盒——计算尺度时须排除，否则整车会被缩小。
    private func normalize(_ root: SCNNode) {
        root.enumerateChildNodes { node, _ in
            node.camera = nil
        }
        let (min, max) = bodyBounds(of: root)
        let center = SCNVector3((min.x + max.x) * 0.5, (min.y + max.y) * 0.5, (min.z + max.z) * 0.5)
        let scale = Float(2.2) / Swift.max(max.x - min.x, max.z - min.z)   // 以车长归一
        root.position = SCNVector3(-center.x * scale, -min.y * scale, -center.z * scale)
        root.scale = SCNVector3(scale, scale, scale)
    }

    /// 只统计车身本体的包围盒（排除灯光网格/阴影/光束等非车身几何）
    private func bodyBounds(of root: SCNNode) -> (min: SCNVector3, max: SCNVector3) {
        let excluded = ["shadow", "light", "beam", "lon", "glow"]
        var mn = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var mx = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        var counted = 0
        root.enumerateChildNodes { node, _ in
            guard let geo = node.geometry else { return }
            let n = node.name?.lowercased() ?? ""
            if excluded.contains(where: { n.contains($0) }) { return }
            let (lmin, lmax) = geo.boundingBox
            let t = node.worldTransform
            for corner in boxCorners(lmin, lmax) {
                let w = SCNVector3(
                    t.m11 * corner.x + t.m12 * corner.y + t.m13 * corner.z + t.m14,
                    t.m21 * corner.x + t.m22 * corner.y + t.m23 * corner.z + t.m24,
                    t.m31 * corner.x + t.m32 * corner.y + t.m33 * corner.z + t.m34
                )
                mn = SCNVector3(min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z))
                mx = SCNVector3(max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z))
            }
            counted += 1
        }
        // 兜底：若过滤后为空（其他车型命名不同），退回全量
        if counted == 0 {
            return fullBounds(of: root)
        }
        return (mn, mx)
    }

    private func fullBounds(of root: SCNNode) -> (min: SCNVector3, max: SCNVector3) {
        var mn = SCNVector3(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var mx = SCNVector3(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)
        root.enumerateChildNodes { node, _ in
            guard let geo = node.geometry else { return }
            let (lmin, lmax) = geo.boundingBox
            let t = node.worldTransform
            for corner in boxCorners(lmin, lmax) {
                let w = SCNVector3(
                    t.m11 * corner.x + t.m12 * corner.y + t.m13 * corner.z + t.m14,
                    t.m21 * corner.x + t.m22 * corner.y + t.m23 * corner.z + t.m24,
                    t.m31 * corner.x + t.m32 * corner.y + t.m33 * corner.z + t.m34
                )
                mn = SCNVector3(min(mn.x, w.x), min(mn.y, w.y), min(mn.z, w.z))
                mx = SCNVector3(max(mx.x, w.x), max(mx.y, w.y), max(mx.z, w.z))
            }
        }
        if mn.x > mx.x { return (SCNVector3Zero, SCNVector3Zero) }
        return (mn, mx)
    }

    // MARK: 部件索引

    /// 三级节点查找：① 精确名 ② 包含匹配（容忍 ModelIO 追加后缀） ③ 模糊关键词
    private func findNode(in root: SCNNode, exact: String?, patterns: [String]) -> SCNNode? {
        if let exact = exact {
            var found: SCNNode?
            root.enumerateChildNodes { node, _ in
                if found == nil, node.name == exact { found = node }
            }
            if found == nil {
                let key = exact.lowercased()
                root.enumerateChildNodes { node, _ in
                    if found == nil, let n = node.name?.lowercased(), n.contains(key) { found = node }
                }
            }
            if let found = found { return found }
        }
        var fuzzy: SCNNode?
        root.enumerateChildNodes { node, _ in
            if fuzzy != nil { return }
            guard let n = node.name?.lowercased(), !n.isEmpty else { return }
            if patterns.contains(where: { n.contains($0) }) { fuzzy = node }
        }
        return fuzzy
    }

    /// 当前模型实际可用的可控部件（无独立节点的部件不会出现，如 C211 无机盖/充电口）
    public var availableParts: Set<CarPart> { Set(partNodes.keys) }

    /// 是否有可独立升降的车窗节点
    public var hasWindows: Bool { !windowNodes.isEmpty }

    /// 由任意子节点向上查找所属可控部件（长按车模触控点控车用）。
    /// 车窗/灯光网格是车门部件的子节点，命中车窗时按车门处理（车窗随车门联动）。
    public func part(containing node: SCNNode) -> CarPart? {
        var current: SCNNode? = node
        while let n = current {
            for (part, partNode) in partNodes where partNode === n {
                return part
            }
            current = n.parent
        }
        return nil
    }

    private func indexParts(in root: SCNNode) {
        var matched: [CarPart: SCNNode] = [:]
        for part in CarPart.allCases {
            if let node = findNode(in: root, exact: part.c211Node, patterns: part.patterns) {
                matched[part] = node
            }
        }
        partNodes = matched
        for (part, node) in matched {
            partRestPositions[part] = node.position
        }
        for part in CarPart.allCases {
            partAngles[part] = 0
        }
    }

    /// 车窗节点（C211 为车门子节点 Window_FL_P 等；其他车型尝试 door 的 glass 子节点）
    private func indexWindows(in root: SCNNode) {
        var matched: [CarPart: SCNNode] = [:]
        for part in CarPart.allCases {
            if let node = findNode(in: root, exact: part.c211WindowNode, patterns: []) {
                matched[part] = node
            }
        }
        // 兜底：在已匹配车门下找 glass/window 子节点（天窗除外——其控制器即部件节点自身）
        for (part, doorNode) in partNodes {
            guard matched[part] == nil, part != .sunroof else { continue }
            doorNode.enumerateChildNodes { node, _ in
                if matched[part] != nil { return }
                let n = node.name?.lowercased() ?? ""
                if n.contains("window") || n.contains("glass") {
                    if node.geometry != nil { matched[part] = node }
                }
            }
        }
        windowNodes = matched
        for (part, node) in matched {
            windowRestPositions[part] = node.position
        }
    }

    /// 门把手节点（C211：Handle_FL_P 等）
    private func indexHandles(in root: SCNNode) {
        var matched: [CarPart: SCNNode] = [:]
        for part in CarPart.allCases {
            if let node = findNode(in: root, exact: part.c211HandleNode, patterns: ["handle"]) {
                matched[part] = node
            }
        }
        handleNodes = matched
    }

    private func indexWheels(in root: SCNNode) {
        let rules: [(WheelPosition, [String])] = [
            (.frontLeft,  ["wheel_fl", "wheelfrontleft", "wheel_lf", "wheel-lf", "luntai_fl", "左前轮"]),
            (.frontRight, ["wheel_fr", "wheelfrontright", "wheel_rf", "wheel-rf", "luntai_fr", "右前轮"]),
            (.rearLeft,   ["wheel_bl", "wheel_lb", "wheel-b", "wheelrearleft", "wheel_lb", "luntai_rl", "左后轮"]),
            (.rearRight,  ["wheel_br", "wheel_rb", "wheelrearright", "wheel_rb", "luntai_rr", "右后轮"]),
        ]
        // C211 后轮为左右镜像单节点 Wheel_B_P：先按精确名匹配
        if let rear = findNode(in: root, exact: "Wheel_B_P", patterns: []) {
            wheelNodes[.rearLeft] = rear
            wheelNodes[.rearRight] = rear
        }
        if let fl = findNode(in: root, exact: "Wheel_FL_P", patterns: []) { wheelNodes[.frontLeft] = fl }
        if let fr = findNode(in: root, exact: "Wheel_FR_P", patterns: []) { wheelNodes[.frontRight] = fr }
        // 其他车型模糊匹配
        root.enumerateChildNodes { node, _ in
            let n = node.name?.lowercased() ?? ""
            guard !n.isEmpty else { return }
            for (pos, keys) in rules where self.wheelNodes[pos] == nil {
                if keys.contains(where: { n.contains($0) }) {
                    self.wheelNodes[pos] = node
                }
            }
        }
    }

    // MARK: 部件控制

    /// 设置某个部件开合（带动画，角度/平移均取自官方动画）
    public func setPart(_ part: CarPart, open: Bool, duration: TimeInterval = 0.35) {
        guard let node = partNodes[part] else { return }
        applyPartPose(part, node: node, open: open, duration: duration)
        // 车门联动降窗（官方随车门开启自动下沉）
        if lowerWindowsWithDoors,
           case .door = partCategory(part),
           let win = windowNodes[part] {
            setWindowNode(win, part: part, open: open, duration: duration)
        }
    }

    private func partCategory(_ part: CarPart) -> PartCategory {
        switch part {
        case .doorFrontLeft, .doorFrontRight, .doorRearLeft, .doorRearRight: return .door
        case .trunk: return .trunk
        case .sunroof: return .sunroof
        default: return .other
        }
    }

    private enum PartCategory { case door, trunk, sunroof, other }

    /// 官方开合姿态（弧度/局部坐标）。translation 仅为开启目标位；关闭位取加载时记录的原位。
    private func c211Pose(for part: CarPart, open: Bool) -> PartPose? {
        let deg = Float.pi / 180
        switch part {
        case .doorFrontLeft, .doorRearLeft:
            return PartPose(rotation: SCNVector3(0, open ? -75 * deg : 0, 0), translation: nil)
        case .doorFrontRight, .doorRearRight:
            return PartPose(rotation: SCNVector3(0, open ? 75 * deg : 0, 0), translation: nil)
        case .trunk:
            return PartPose(rotation: SCNVector3(open ? 70 * deg : 0, 0, 0), translation: nil)
        case .sunroof:
            // 官方：关闭 (-0.0001, 1.4854, -0.1019) → 开启 (0, 1.4746, -0.6172)，绕 -X 翻转 7.11°
            let t: SCNVector3? = open ? SCNVector3(0, 1.4746, -0.6172) : partRestPositions[part]
            return PartPose(rotation: SCNVector3(open ? -7.11 * deg : 0, 0, 0), translation: t)
        default:
            return nil
        }
    }

    private struct PartPose {
        var rotation: SCNVector3
        var translation: SCNVector3?
    }

    private func applyPartPose(_ part: CarPart, node: SCNNode, open: Bool, duration: TimeInterval) {
        if let pose = c211Pose(for: part, open: open) {
            node.removeAllActions()
            let rot = SCNAction.rotateTo(
                x: CGFloat(pose.rotation.x), y: CGFloat(pose.rotation.y), z: CGFloat(pose.rotation.z),
                duration: duration)
            rot.timingMode = .easeInEaseOut
            node.runAction(rot)
            if let t = pose.translation {
                let move = SCNAction.move(to: t, duration: duration)
                move.timingMode = .easeInEaseOut
                node.runAction(move)
            }
            partAngles[part] = abs(pose.rotation.x) + abs(pose.rotation.y) + abs(pose.rotation.z)
            return
        }

        // 其他车型兜底：门 60°、后备箱/机盖 75°，按所在侧决定符号
        let maxAngle: Float = (part == .trunk || part == .hood) ? Float(75 * Double.pi / 180)
                                                               : Float(60 * Double.pi / 180)
        let target = open ? maxAngle : 0
        let sign: Float = node.position.x > 0 ? -1 : 1
        node.removeAllActions()
        let rotate = SCNAction.rotateTo(x: 0, y: CGFloat(target * sign), z: 0, duration: duration)
        rotate.timingMode = .easeInEaseOut
        node.runAction(rotate)
        partAngles[part] = open ? maxAngle : 0
    }

    /// 单独控制某个车窗/天窗（官方下沉量：前门 9.28cm / 后门 9.55cm，外倾 2.97°）
    public func setWindow(_ part: CarPart, open: Bool, duration: TimeInterval = 0.35) {
        guard let win = windowNodes[part] else { return }
        setWindowNode(win, part: part, open: open, duration: duration)
    }

    private func setWindowNode(_ node: SCNNode, part: CarPart, open: Bool, duration: TimeInterval) {
        let deg = Float.pi / 180
        // C211 官方车窗开启位（局部坐标，来自动画末帧）
        let openPos: SCNVector3?
        let tilt: Float
        switch part {
        case .doorFrontLeft:  openPos = SCNVector3(-0.1333, 0.3208, -0.7349); tilt = -2.97 * deg
        case .doorFrontRight: openPos = SCNVector3(0.1333, 0.3208, -0.7349);  tilt = 2.97 * deg
        case .doorRearLeft:   openPos = SCNVector3(-0.1494, 0.3306, -0.4983); tilt = -2.97 * deg
        case .doorRearRight:  openPos = SCNVector3(0.1494, 0.3306, -0.4983);  tilt = 2.97 * deg
        case .sunroof:        openPos = nil; tilt = 0     // 天窗由 setPart(.sunroof) 处理
        default:              openPos = nil; tilt = 0
        }
        node.removeAllActions()
        if let target = open ? openPos : windowRestPositions[part] {
            let move = SCNAction.move(to: target, duration: duration)
            move.timingMode = .easeInEaseOut
            node.runAction(move)
            let rot = SCNAction.rotateTo(x: 0, y: 0, z: CGFloat(open ? tilt : 0), duration: duration)
            rot.timingMode = .easeInEaseOut
            node.runAction(rot)
        } else {
            // 兜底：沿局部 Y 下沉 0.1
            let move = SCNAction.moveBy(x: 0, y: open ? -0.1 : 0.1, z: 0, duration: duration)
            move.timingMode = .easeInEaseOut
            node.runAction(move)
        }
    }

    /// 便捷方法：与引力域 openDoor/openLock 语义对齐
    public func setDoorOpen(_ open: Bool) {
        setPart(.doorFrontLeft, open: open)
        setPart(.doorFrontRight, open: open)
        setPart(.doorRearLeft, open: open)
        setPart(.doorRearRight, open: open)
    }

    public func setTrunkOpen(_ open: Bool) { setPart(.trunk, open: open) }
    public func setHoodOpen(_ open: Bool)   { setPart(.hood, open: open) }
    public func setSunroofOpen(_ open: Bool) { setPart(.sunroof, open: open) }
    public func setChargePortOpen(_ open: Bool) { setPart(.chargePort, open: open) }

    // MARK: 门把手（解锁弹出）

    /// 四门把手弹出/收回（官方 10° 翻转）；通常随解锁状态联动
    public func setHandlesOpen(_ open: Bool, duration: TimeInterval = 0.3) {
        let deg = Float.pi / 180
        for (part, node) in handleNodes {
            node.removeAllActions()
            let angle: Float = open ? (part.isLeftSide ? -10.01 * deg : 10.01 * deg) : 0
            let rot = SCNAction.rotateTo(x: 0, y: CGFloat(angle), z: 0, duration: duration)
            rot.timingMode = .easeInEaseOut
            node.runAction(rot)
        }
    }

    /// 锁/解锁状态：解锁 → 把手弹出；上锁 → 把手收回（并关门）
    public func setUnlocked(_ unlocked: Bool, animated: Bool = true) {
        isUnlocked = unlocked
        applyLockState(animated: animated)
    }

    private func applyLockState(animated: Bool) {
        setHandlesOpen(isUnlocked, duration: animated ? 0.3 : 0.001)
    }

    // MARK: 车轮

    public func startWheels(rpm: Float = 4) {
        guard !isWheelsSpinning, !wheelNodes.isEmpty else { return }
        isWheelsSpinning = true
        // 相对旋转（rotateBy）才能无缝循环；rotateTo 会在每圈结束跳变回 0
        // 绕节点局部 X 轴（轮轴方向；C211 车轮节点 rest 旋转为单位四元数，局部 X = 世界 X）
        let perRev = SCNAction.rotateBy(x: CGFloat(2 * Double.pi), y: 0, z: 0, duration: 60 / Double(rpm))
        perRev.timingMode = .linear
        let forever = SCNAction.repeatForever(perRev)
        // 后轮为左右镜像单节点（Wheel_B_P），去重后只跑一个 action
        var seen = Set<ObjectIdentifier>()
        for node in wheelNodes.values {
            let id = ObjectIdentifier(node)
            if seen.contains(id) { continue }
            seen.insert(id)
            node.runAction(forever, forKey: "spin")
        }
    }

    public func stopWheels() {
        isWheelsSpinning = false
        var seen = Set<ObjectIdentifier>()
        for node in wheelNodes.values {
            let id = ObjectIdentifier(node)
            if seen.contains(id) { continue }
            seen.insert(id)
            node.removeAction(forKey: "spin")
        }
    }

    // MARK: 灯光控制

    /// 灯光分组（对应 C211 官方 LOn 自发光网格命名）
    public enum LightGroup: String, CaseIterable {
        case headlight   // 前照灯 + DRL + 示宽
        case taillight   // 尾灯
        case brake       // 刹车灯
        case doorLight   // 门灯（解锁/开门点亮）

        /// C211 官方节点名（网格自带自发光贴图，显隐即开关）
        var c211Nodes: [String] {
            switch self {
            case .headlight:  return ["Light_HL_LOn_Ext", "Light_DRL_LOn_Ext", "Light_L_LOn_Ext", "Light_R_LOn_Ext"]
            case .taillight:  return ["Light_TL_LOn_Ext", "Light_TL_LOn_LuggageDoor"]
            case .brake:      return ["Light_BL_LOn_Ext", "Light_BL_LOn_LuggageDoor"]
            case .doorLight:  return ["Light_L_LOn_Door_FL", "Light_R_LOn_Door_FR"]
            }
        }

        /// 其他车型模糊匹配
        var patterns: [String] {
            switch self {
            case .headlight:  return ["headlight", "light_hl", "_hl_", "drl", "positionlamp", "示宽"]
            case .taillight:  return ["taillight", "light_tl", "_tl_", "尾灯"]
            case .brake:      return ["brake", "light_bl", "_bl_", "刹车"]
            case .doorLight:  return ["light_l_lon_door", "light_r_lon_door", "doorlight"]
            }
        }
    }

    private func indexLights(in root: SCNNode) {
        var groups: [LightGroup: [SCNNode]] = [:]
        for group in LightGroup.allCases {
            var nodes: [SCNNode] = []
            // 1) C211 精确名（含包含匹配兜底）
            for exact in group.c211Nodes {
                if let node = findNode(in: root, exact: exact, patterns: []) {
                    nodes.append(node)
                }
            }
            // 2) 模糊兜底（仅 C211 名未命中时）
            if nodes.isEmpty {
                root.enumerateChildNodes { node, _ in
                    guard node.geometry != nil else { return }
                    let n = node.name?.lowercased() ?? ""
                    guard !n.isEmpty else { return }
                    if group.patterns.contains(where: { n.contains($0) }) {
                        nodes.append(node)
                    }
                }
            }
            // LOn 网格默认全隐藏（官方 App 中 visible:false），由状态驱动显隐
            nodes.forEach { $0.isHidden = true }
            groups[group] = nodes
        }
        lightGroups = groups
    }

    /// 灯光总控
    /// - Parameters:
    ///   - headlight: 前灯 + DRL + 示宽灯
    ///   - taillight: 尾灯（示宽同亮）
    ///   - brake: 刹车灯（含尾门刹车灯）
    public func setLights(headlight: Bool, taillight: Bool = false, brake: Bool = false) {
        applyLights(headlight: headlight, taillight: taillight, brake: brake)
        // 门灯随解锁状态
        applyDoorLights(on: isUnlocked)
    }

    /// 兼容旧 API：刹车/示宽灯开关
    public func setLights(brakeOn: Bool) {
        setLights(headlight: false, taillight: brakeOn, brake: brakeOn)
    }

    private func applyLights(headlight: Bool, taillight: Bool, brake: Bool) {
        lightGroups[.headlight]?.forEach { $0.isHidden = !headlight }
        lightGroups[.taillight]?.forEach { $0.isHidden = !(taillight || brake) }
        lightGroups[.brake]?.forEach { $0.isHidden = !brake }
    }

    private func applyLightState(animated: Bool) {
        applyLights(headlight: false, taillight: false, brake: false)
        applyDoorLights(on: isUnlocked)
    }

    private func applyDoorLights(on: Bool) {
        lightGroups[.doorLight]?.forEach { $0.isHidden = !on }
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

// MARK: - 工具

private func boxCorners(_ min: SCNVector3, _ max: SCNVector3) -> [SCNVector3] {
    [
        SCNVector3(min.x, min.y, min.z), SCNVector3(max.x, min.y, min.z),
        SCNVector3(min.x, max.y, min.z), SCNVector3(max.x, max.y, min.z),
        SCNVector3(min.x, min.y, max.z), SCNVector3(max.x, min.y, max.z),
        SCNVector3(min.x, max.y, max.z), SCNVector3(max.x, max.y, max.z),
    ]
}
