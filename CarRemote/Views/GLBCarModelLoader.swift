//
//  GLBCarModelLoader.swift
//  长安控车 — 「我的爱车」GLB 车模零依赖解析器
//
//  资产来源：从「我的爱车」App（com.kancher.kc2026）提取的 12 款长安系 3D 车模
//  （GLB 2.0 格式），已离线预处理：meshopt 压缩已解码还原、动画已剔除、
//  贴图保留 WebP（iOS 14+ ImageIO 原生解码）、顶点保留量化 SHORT/BYTE
//  （本解析器原生反量化），因此单模型体积控制在 2~6MB。
//
//  解析产物：与 Car3DView 现有 .rk 管线同一结构（RKCarModel），且**带完整联动**：
//  官方 *_P 铰链枢轴（Door_FL_P 四门 / LuggageDoor_P 尾门 / Window_T_P 天窗 /
//  Window_*_P 车窗 / Handle_*_P 把手 / Wheel_*_P 车轮）原样保留为部件实体，
//  长按点选、车况联动、车轮滚动全部可用；车灯已在离线预处理阶段关闭
//  （移除 LOn 自发光网格并清零 emissive），完整复用轨道相机与挂载系统。
//
//  glTF 规范要点（本文件按此实现）：
//    - 右手坐标系、+Y 向上；RealityKit 同为右手 +Y 向上，无需轴变换
//    - 节点变换：local = T * R * S（matrix 字段为列主序 4×4）
//    - UV 原点在左上（与 Metal/RealityKit 一致，无需翻转 V）
//    - KHR_mesh_quantization：normalized 分量除以 (2^(n-1)-1)（有符号）
//      或 (2^n - 1)（无符号）反量化
//

import Foundation
import RealityKit
import UIKit
import ImageIO

enum GLBCarModelLoader {

    enum GLBError: Error {
        case badMagic, badVersion, missingJSON, badJSON, missingBIN, badGeometry
    }

    // MARK: - 顶层入口（后台线程调用）

    /// 按资源名加载 Bundle 内的 .glb 车模（XcodeGen 打包层级可能扁平化，多路径兜底）。
    ///
    /// 配色变体约定：资源名以 `_gray` 结尾（如 `c211_gray`）→ 复用同文件车模
    /// 并对车漆整体乘一层更深的灰色调（网页版逸动 #C6C6C6 再加深）。
    static func load(named name: String) -> RKCarModel? {
        var res = name
        var tint: SIMD4<Float>? = nil
        if res.hasSuffix("_gray") {
            res = String(res.dropLast(5))
            // 线性空间乘色：0.46 → sRGB ≈ #B0B2B5，比网页版 #C6C6C6 深一档
            tint = SIMD4<Float>(0.46, 0.47, 0.49, 1)
        }
        guard let url = resourceURL(named: res, ext: "glb"),
              let data = try? Data(contentsOf: url) else { return nil }
        return build(from: data, tint: tint)
    }

    static func resourceURL(named name: String, ext: String) -> URL? {
        if let u = Bundle.main.url(forResource: name, withExtension: ext) { return u }
        for sub in ["3DModel/Gallery", "Gallery", "3DModel"] {
            if let u = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: sub) {
                return u
            }
        }
        return nil
    }

    // MARK: - 轻量结构

    private struct BufferView {
        let buffer: Int
        let byteOffset: Int
        let byteLength: Int
        let byteStride: Int
    }

    private struct Accessor {
        let bufferView: Int?
        let byteOffset: Int
        let componentType: Int
        let count: Int
        let type: String
        let normalized: Bool
    }

    /// 材质参数（glTF PBR 子集）
    private struct MatParams {
        var name: String = ""
        var baseColor = SIMD4<Float>(1, 1, 1, 1)
        var metallic: Float = 1
        var roughness: Float = 1
        var alphaMode: String = "OPAQUE"
        var doubleSided = false
        var textureIndex: Int?
    }

    // MARK: - GLB 构建主流程

    static func build(from data: Data, tint: SIMD4<Float>? = nil) -> RKCarModel? {
        do {
            let (json, bin) = try parseGLB(data)
            guard let buffers = json["buffers"] as? [[String: Any]],
                  buffers.count >= 1 else { throw GLBError.badGeometry }

            let views = (json["bufferViews"] as? [[String: Any]] ?? []).map { d -> BufferView in
                BufferView(buffer: d["buffer"] as? Int ?? 0,
                           byteOffset: d["byteOffset"] as? Int ?? 0,
                           byteLength: d["byteLength"] as? Int ?? 0,
                           byteStride: d["byteStride"] as? Int ?? 0)
            }
            let accessors = (json["accessors"] as? [[String: Any]] ?? []).map { d -> Accessor in
                Accessor(bufferView: d["bufferView"] as? Int,
                         byteOffset: d["byteOffset"] as? Int ?? 0,
                         componentType: d["componentType"] as? Int ?? 5126,
                         count: d["count"] as? Int ?? 0,
                         type: d["type"] as? String ?? "VEC3",
                         normalized: d["normalized"] as? Bool ?? false)
            }
            let meshes = json["meshes"] as? [[String: Any]] ?? []
            let materialsJSON = json["materials"] as? [[String: Any]] ?? []
            let texturesJSON = json["textures"] as? [[String: Any]] ?? []
            let imagesJSON = json["images"] as? [[String: Any]] ?? []
            let nodesJSON = json["nodes"] as? [[String: Any]] ?? []
            let scenesJSON = json["scenes"] as? [[String: Any]] ?? []

            // ---- 贴图：image 字节 → CGImage → TextureResource（WebP/PNG/JPEG 通吃）----
            var imageTextures: [Int: TextureResource] = [:]
            for (ti, t) in texturesJSON.enumerated() {
                guard let src = t["source"] as? Int, src < imagesJSON.count else { continue }
                let img = imagesJSON[src]
                guard let bvi = img["bufferView"] as? Int, bvi < views.count else { continue }
                let v = views[bvi]
                guard v.byteOffset + v.byteLength <= bin.count else { continue }
                let bytes = bin.subdata(in: v.byteOffset..<(v.byteOffset + v.byteLength))
                if let tex = makeTexture(from: bytes) { imageTextures[ti] = tex }
            }

            // ---- 材质 ----
            var materials: [MatParams] = materialsJSON.map { m -> MatParams in
                var p = MatParams()
                p.name = m["name"] as? String ?? ""
                if let pbr = m["pbrMetallicRoughness"] as? [String: Any] {
                    if let c = pbr["baseColorFactor"] as? [Double], c.count >= 3 {
                        p.baseColor = SIMD4<Float>(Float(c[0]), Float(c[1]), Float(c[2]),
                                                   Float(c.count > 3 ? c[3] : 1))
                    }
                    if let mf = pbr["metallicFactor"] as? Double { p.metallic = Float(mf) }
                    if let rf = pbr["roughnessFactor"] as? Double { p.roughness = Float(rf) }
                    if let bct = pbr["baseColorTexture"] as? [String: Any] {
                        p.textureIndex = bct["index"] as? Int
                    }
                }
                p.alphaMode = m["alphaMode"] as? String ?? "OPAQUE"
                p.doubleSided = m["doubleSided"] as? Bool ?? false
                return p
            }
            // 无 material 字段的 primitive 用默认材质
            if materials.isEmpty { materials = [MatParams()] }

            // ---- 几何：按节点树构建，「我的爱车」官方 *_P 铰链枢轴 → 部件联动 ----
            //
            // 官方模型骨架（5 款同源，已逐款核验）：
            //   Door_FL/FR/BL/BR_P  四门铰链枢轴（绕局部 Y 轴 ±75°）
            //   LuggageDoor_P       尾门枢轴（绕局部 X 轴 +70°）
            //   Window_T_P          天窗枢轴（后滑 + 7.11° 上翻）
            //   Window_FL/FR/BL/BR_P 车窗玻璃枢轴（下行 ~0.14m + ±2.97° 微倾）
            //   Handle_FL/FR/BL/BR_P 门把手枢轴（解锁弹出 ±10.01°）
            //   Wheel_FL/FR/B_P(+Roll_P) 车轮（绕 X 轴滚动）
            //
            // 烘焙策略（与 .rk 管线一致，保证开合动画直接改 rotation 不破坏静止姿态）：
            //   枢轴实体 = 纯平移（铰链世界坐标），几何顶点按「最近枢轴祖先的世界平移」
            //   烘焙到铰链局部空间 —— 顶点世界位 = 局部位 + 铰链平移。
            let carRoot = Entity()
            carRoot.name = "carRoot_glb"

            var worldMatrices = [simd_float4x4](repeating: matrix_identity_float4x4,
                                                count: max(nodesJSON.count, 1))
            var accessorFloatCache: [Int: [Float]] = [:]
            var accessorIndexCache: [Int: [UInt32]] = [:]
            var materialCache: [Int: PhysicallyBasedMaterial] = [:]

            var boundsMin = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
            var boundsMax = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
            let fitBuckets = 96, fitLayers = 8
            var fitBest = [Float](repeating: -1, count: fitBuckets * fitLayers)
            var fitReps = [SIMD3<Float>](repeating: .zero, count: fitBuckets * fitLayers)

            func worldMatrix(node: Int, parent: simd_float4x4) -> simd_float4x4 {
                let local = localMatrix(nodesJSON[node])
                let w = parent * local
                worldMatrices[node] = w
                if let children = nodesJSON[node]["children"] as? [Int] {
                    for c in children where c < nodesJSON.count {
                        _ = worldMatrix(node: c, parent: w)
                    }
                }
                return w
            }

            let rootNodes: [Int]
            let sceneIdx = json["scene"] as? Int ?? 0
            if sceneIdx < scenesJSON.count,
               let rn = scenesJSON[sceneIdx]["nodes"] as? [Int] {
                rootNodes = rn
            } else {
                rootNodes = Array(0..<nodesJSON.count)
            }
            for r in rootNodes where r < nodesJSON.count {
                _ = worldMatrix(node: r, parent: matrix_identity_float4x4)
            }

            // ---- 官方枢轴分类 ----
            enum PivotKind { case door, trunk, sunroof, window, handle, wheel }
            struct PivotSpec {
                let kind: PivotKind
                let part: CarPart?
                let wheel: WheelPosition?
                let tiltSign: Float   // 官方开合方向符号（左门− 右门+，尾门/天窗 +）
            }
            func classifyPivot(_ name: String) -> PivotSpec? {
                if name.hasSuffix("_Roll_P") { return nil }   // 滚转子枢轴跟随车轮实体
                switch name {
                case "Door_FL_P":      return PivotSpec(kind: .door, part: .doorFrontLeft, wheel: nil, tiltSign: -1)
                case "Door_FR_P":      return PivotSpec(kind: .door, part: .doorFrontRight, wheel: nil, tiltSign: 1)
                case "Door_BL_P":      return PivotSpec(kind: .door, part: .doorRearLeft, wheel: nil, tiltSign: -1)
                case "Door_BR_P":      return PivotSpec(kind: .door, part: .doorRearRight, wheel: nil, tiltSign: 1)
                case "LuggageDoor_P":  return PivotSpec(kind: .trunk, part: .trunk, wheel: nil, tiltSign: 1)
                case "Window_T_P":     return PivotSpec(kind: .sunroof, part: .sunroof, wheel: nil, tiltSign: 1)
                case "Window_FL_P":    return PivotSpec(kind: .window, part: .doorFrontLeft, wheel: nil, tiltSign: -1)
                case "Window_FR_P":    return PivotSpec(kind: .window, part: .doorFrontRight, wheel: nil, tiltSign: 1)
                case "Window_BL_P":    return PivotSpec(kind: .window, part: .doorRearLeft, wheel: nil, tiltSign: -1)
                case "Window_BR_P":    return PivotSpec(kind: .window, part: .doorRearRight, wheel: nil, tiltSign: 1)
                case "Handle_FL_P":    return PivotSpec(kind: .handle, part: .doorFrontLeft, wheel: nil, tiltSign: -1)
                case "Handle_FR_P":    return PivotSpec(kind: .handle, part: .doorFrontRight, wheel: nil, tiltSign: 1)
                case "Handle_BL_P":    return PivotSpec(kind: .handle, part: .doorRearLeft, wheel: nil, tiltSign: -1)
                case "Handle_BR_P":    return PivotSpec(kind: .handle, part: .doorRearRight, wheel: nil, tiltSign: 1)
                case "Wheel_FL_P":     return PivotSpec(kind: .wheel, part: nil, wheel: .frontLeft, tiltSign: 1)
                case "Wheel_FR_P":     return PivotSpec(kind: .wheel, part: nil, wheel: .frontRight, tiltSign: 1)
                case "Wheel_B_P":      return PivotSpec(kind: .wheel, part: nil, wheel: .rearLeft, tiltSign: 1)  // 后轴合成件
                default: return nil
                }
            }
            // 部件实体命名：part(at:) 沿祖先链查名（doorFL/doorFR/doorBL/doorBR/trunk/sunroof），
            // 车窗/把手/车轮沿用 .rk 管线同款命名（windowFL/handleFL/wheelFL…）
            func entityName(for spec: PivotSpec) -> String {
                let suffix: String
                switch spec.part ?? (spec.wheel == .frontLeft ? .doorFrontLeft :
                                     spec.wheel == .frontRight ? .doorFrontRight : .doorRearLeft) {
                case .doorFrontLeft: suffix = "FL"
                case .doorFrontRight: suffix = "FR"
                case .doorRearLeft: suffix = "BL"
                case .doorRearRight: suffix = "BR"
                default: suffix = "B"
                }
                switch spec.kind {
                case .door: return "door\(suffix)"
                case .trunk: return "trunk"
                case .sunroof: return "sunroof"
                case .window: return "window\(suffix)"
                case .handle: return "handle\(suffix)"
                case .wheel: return "wheel\(suffix)"
                }
            }

            // ---- 单次 DFS：建枢轴实体（纯平移）+ 记录每个网格节点的归属枢轴 ----
            var pivotEntities = [Int: Entity]()
            var pivotFrames = [Int: SIMD3<Float>]()      // 枢轴世界平移（根空间）
            var pivotSpecByNode = [Int: PivotSpec]()
            var ownerPivotOf = [Int: Int]()              // 网格节点 → 最近枢轴祖先
            func dfsBuild(node: Int, nearestPivot: Int?) {
                guard node < nodesJSON.count else { return }
                let name = nodesJSON[node]["name"] as? String ?? ""
                if let spec = classifyPivot(name) {
                    let w = worldMatrices[node]
                    let t = SIMD3<Float>(w.columns.3.x, w.columns.3.y, w.columns.3.z)
                    let e = Entity()
                    if let np = nearestPivot, let pe = pivotEntities[np], let pf = pivotFrames[np] {
                        e.position = t - pf
                        pe.addChild(e)
                    } else {
                        e.position = t
                        carRoot.addChild(e)
                    }
                    e.name = entityName(for: spec)
                    pivotEntities[node] = e
                    pivotFrames[node] = t
                    pivotSpecByNode[node] = spec
                    if let children = nodesJSON[node]["children"] as? [Int] {
                        for c in children { dfsBuild(node: c, nearestPivot: node) }
                    }
                } else {
                    if let np = nearestPivot { ownerPivotOf[node] = np }
                    if let children = nodesJSON[node]["children"] as? [Int] {
                        for c in children { dfsBuild(node: c, nearestPivot: nearestPivot) }
                    }
                }
            }
            for r in rootNodes where r < nodesJSON.count {
                dfsBuild(node: r, nearestPivot: nil)
            }

            // ---- 网格：顶点按归属枢轴烘焙到铰链局部空间 ----
            var primitiveCounter = 0
            var fitRecorded = Set<Int>()
            /// (铰链局部顶点缓存, 链接平移) —— bounds 就绪后统一扫描取景代表点
            var deferredFit: [(verts: [SIMD3<Float>], frame: SIMD3<Float>)] = []
            for (ni, node) in nodesJSON.enumerated() {
                guard let meshIdx = node["mesh"] as? Int, meshIdx < meshes.count else { continue }
                let world = worldMatrices[ni]
                // 归属枢轴的世界平移（根空间）：顶点局部 = 世界位 − 铰链平移
                let frameT: SIMD3<Float>
                if let owner = ownerPivotOf[ni], let f = pivotFrames[owner] {
                    frameT = f
                } else {
                    frameT = .zero
                }
                let parentEntity = ownerPivotOf[ni].flatMap { pivotEntities[$0] } ?? carRoot

                let prims = meshes[meshIdx]["primitives"] as? [[String: Any]] ?? []
                for prim in prims {
                    guard (prim["mode"] as? Int ?? 4) == 4 else { continue }   // 仅三角形
                    guard let attrs = prim["attributes"] as? [String: Int],
                          let posIdx = attrs["POSITION"], posIdx < accessors.count else { continue }

                    // 顶点
                    let posFlat: [Float]
                    if let cached = accessorFloatCache[posIdx] { posFlat = cached }
                    else {
                        posFlat = readFloats(accessors[posIdx], views: views, bin: bin)
                        accessorFloatCache[posIdx] = posFlat
                    }
                    guard posFlat.count >= (accessors[posIdx].count * 3) else { continue }
                    let vc = accessors[posIdx].count

                    // 索引（无索引则顺序索引）
                    var indices: [UInt32]
                    if let ii = prim["indices"] as? Int, ii < accessors.count {
                        if let cached = accessorIndexCache[ii] { indices = cached }
                        else {
                            indices = readIndices(accessors[ii], views: views, bin: bin)
                            accessorIndexCache[ii] = indices
                        }
                    } else {
                        indices = Array(0..<UInt32(vc))
                    }
                    if indices.count % 3 != 0 { indices.removeLast(indices.count % 3) }
                    indices = indices.filter { Int($0) < vc }
                    guard indices.count >= 3 else { continue }

                    // 烘焙到铰链局部空间（世界位 = 局部位 + 铰链平移）
                    var positions = [SIMD3<Float>](repeating: .zero, count: vc)
                    let col0 = world.columns.0, col1 = world.columns.1
                    let col2 = world.columns.2, col3 = world.columns.3
                    for i in 0..<vc {
                        let x = posFlat[i * 3], y = posFlat[i * 3 + 1], z = posFlat[i * 3 + 2]
                        let lx = col0.x * x + col1.x * y + col2.x * z + col3.x - frameT.x
                        let ly = col0.y * x + col1.y * y + col2.y * z + col3.y - frameT.y
                        let lz = col0.z * x + col1.z * y + col2.z * z + col3.z - frameT.z
                        positions[i] = SIMD3<Float>(lx, ly, lz)
                        let wx = lx + frameT.x, wy = ly + frameT.y, wz = lz + frameT.z
                        boundsMin.x = min(boundsMin.x, wx); boundsMax.x = max(boundsMax.x, wx)
                        boundsMin.y = min(boundsMin.y, wy); boundsMax.y = max(boundsMax.y, wy)
                        boundsMin.z = min(boundsMin.z, wz); boundsMax.z = max(boundsMax.z, wz)
                    }
                    // 取景代表点：同一 POSITION 同一枢轴只缓存一份（铰链局部坐标 + 链接平移），
                    // 待全部包围盒就绪后统一扫描（高度分层依赖完整 bounds）
                    let fitKey = posIdx * 4096 + (ownerPivotOf[ni] ?? nodesJSON.count)
                    if !fitRecorded.contains(fitKey) {
                        fitRecorded.insert(fitKey)
                        deferredFit.append((verts: positions, frame: frameT))
                    }

                    // 法线（缺失时按几何面均值补算）
                    var normals: [SIMD3<Float>]?
                    if let nIdx = attrs["NORMAL"], nIdx < accessors.count {
                        let nf = accessorFloatCache[nIdx] ?? {
                            let v = readFloats(accessors[nIdx], views: views, bin: bin)
                            accessorFloatCache[nIdx] = v
                            return v
                        }()
                        if nf.count >= vc * 3 {
                            let L = simd_float3x3(columns: (SIMD3<Float>(col0.x, col0.y, col0.z),
                                                            SIMD3<Float>(col1.x, col1.y, col1.z),
                                                            SIMD3<Float>(col2.x, col2.y, col2.z)))
                            let nMat = abs(L.determinant) > 1e-8 ? L.inverse.transpose : L
                            normals = [SIMD3<Float>](repeating: .zero, count: vc)
                            for i in 0..<vc {
                                let n = SIMD3<Float>(nf[i * 3], nf[i * 3 + 1], nf[i * 3 + 2])
                                normals![i] = simd_normalize(nMat * n)
                            }
                        }
                    }
                    if normals == nil { normals = computeSmoothNormals(positions: positions, indices: indices) }

                    // UV
                    var uvs: [SIMD2<Float>]?
                    if let uvIdx = attrs["TEXCOORD_0"], uvIdx < accessors.count {
                        let uf = accessorFloatCache[uvIdx] ?? {
                            let v = readFloats(accessors[uvIdx], views: views, bin: bin)
                            accessorFloatCache[uvIdx] = v
                            return v
                        }()
                        if uf.count >= vc * 2 {
                            uvs = [SIMD2<Float>](repeating: .zero, count: vc)
                            for i in 0..<vc { uvs![i] = SIMD2<Float>(uf[i * 2], uf[i * 2 + 1]) }
                        }
                    }

                    // 材质（含贴图缓存）
                    let matIdx = prim["material"] as? Int ?? 0
                    let params = matIdx < materials.count ? materials[matIdx] : MatParams()
                    // 官方模自带的假地面阴影面片与本 App 纯净卡片背景不搭，直接跳过
                    if params.name.lowercased().contains("shadow") { continue }
                    let mat: PhysicallyBasedMaterial
                    if let cached = materialCache[matIdx] { mat = cached }
                    else {
                        mat = makeMaterial(params, textures: imageTextures, tint: tint)
                        materialCache[matIdx] = mat
                    }

                    // 构建网格，挂到归属枢轴实体（无枢轴则挂车根）
                    var descriptor = MeshDescriptor(name: "glb_p\(primitiveCounter)")
                    primitiveCounter += 1
                    descriptor.positions = MeshBuffers.Positions(positions)
                    if let normals { descriptor.normals = MeshBuffers.Normals(normals) }
                    if let uvs { descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs) }
                    descriptor.primitives = .triangles(indices)
                    descriptor.materials = .allFaces(0)
                    guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }
                    let model = ModelEntity(mesh: mesh, materials: [mat])
                    parentEntity.addChild(model)
                }
            }
            guard primitiveCounter > 0 else { return nil }

            // ---- 部件字典装配（角度与 .rk 官方清单一致：门 ±75° / 尾门 70° / 把手 10° / 窗倾 2.97° / 天窗 -7.11°）----
            var partEntities: [CarPart: Entity] = [:]
            var doorTilt: [CarPart: Float] = [:]
            var windowEntities: [CarPart: Entity] = [:]
            var windowRest: [CarPart: SIMD3<Float>] = [:]
            var windowOpen: [CarPart: SIMD3<Float>] = [:]
            var windowTilt: [CarPart: Float] = [:]
            var handleEntities: [CarPart: Entity] = [:]
            var handleTilt: [CarPart: Float] = [:]
            var wheelEntities: [WheelPosition: Entity] = [:]
            var uniqueWheels: [Entity] = []
            var sunroofRest = SIMD3<Float>.zero
            var sunroofOpen = SIMD3<Float>.zero
            var sunroofTilt: Float = 0
            let deg = Float.pi / 180

            for (node, spec) in pivotSpecByNode {
                guard let e = pivotEntities[node] else { continue }
                let rel = e.position   // 相对父枢轴/车根的平移（rest 位）
                switch spec.kind {
                case .door:
                    if let p = spec.part {
                        partEntities[p] = e
                        doorTilt[p] = spec.tiltSign * 75 * deg
                    }
                case .trunk:
                    partEntities[.trunk] = e
                    doorTilt[.trunk] = 70 * deg
                case .sunroof:
                    partEntities[.sunroof] = e
                    sunroofRest = rel
                    sunroofOpen = rel + SIMD3<Float>(0, 0.05, -0.30)   // 官方：后滑 + 上抬，7.11° 翻转
                    sunroofTilt = -7.11 * deg
                case .window:
                    if let p = spec.part {
                        windowEntities[p] = e
                        windowRest[p] = rel
                        windowOpen[p] = rel + SIMD3<Float>(0, -0.14, 0)  // 玻璃下行（与 .rk 官方量级一致）
                        windowTilt[p] = spec.tiltSign * 2.97 * deg
                    }
                case .handle:
                    if let p = spec.part {
                        handleEntities[p] = e
                        handleTilt[p] = spec.tiltSign * 10.01 * deg
                    }
                case .wheel:
                    if let w0 = spec.wheel {
                        wheelEntities[w0] = e
                        if w0 == .rearLeft { wheelEntities[.rearRight] = e }   // 后轴合成件，左右共用
                        if !uniqueWheels.contains(where: { $0 === e }) { uniqueWheels.append(e) }
                    }
                }
            }

            // ---- 取景代表点（与 .rk 管线一致：方位角 × 高度分格取半径最大顶点）----
            guard boundsMin.x <= boundsMax.x else { return nil }
            let ySpan = max(boundsMax.y - boundsMin.y, 1e-5)
            for (verts, frame) in deferredFit {
                for p in verts {
                    let rel = p + frame   // 世界坐标（枢轴帧为纯平移帧）
                    let azf = atan2(rel.x, rel.z)
                    var bi = Int((azf + .pi) / (2 * .pi) * Float(fitBuckets))
                    bi = min(max(bi, 0), fitBuckets - 1)
                    var li = Int((rel.y - boundsMin.y) / ySpan * Float(fitLayers))
                    li = min(max(li, 0), fitLayers - 1)
                    let k = bi * fitLayers + li
                    let r2 = simd_dot(rel, rel)
                    if r2 > fitBest[k] { fitBest[k] = r2; fitReps[k] = rel }
                }
            }
            var fitPoints: [SIMD3<Float>] = []
            fitPoints.reserveCapacity(fitBuckets * fitLayers)
            for k in 0..<(fitBuckets * fitLayers) where fitBest[k] >= 0 {
                fitPoints.append(fitReps[k])
            }

            return RKCarModel(root: carRoot,
                              partEntities: partEntities, windowEntities: windowEntities,
                              handleEntities: handleEntities,
                              wheelEntities: wheelEntities, uniqueWheels: uniqueWheels,
                              lightEntities: [:],
                              doorTilt: doorTilt, sunroofRest: sunroofRest, sunroofOpen: sunroofOpen,
                              sunroofTilt: sunroofTilt, windowRest: windowRest, windowOpen: windowOpen,
                              windowTilt: windowTilt, handleTilt: handleTilt,
                              boundsMin: boundsMin, boundsMax: boundsMax,
                              fitPoints: fitPoints)
        } catch {
            return nil
        }
    }

    // MARK: - GLB 二进制结构

    private static func parseGLB(_ data: Data) throws -> ([String: Any], Data) {
        guard data.count >= 12,
              data.withUnsafeBytes({ $0.load(as: UInt32.self) }) == 0x46546C67 else {   // 'glTF'
            throw GLBError.badMagic
        }
        var off = 12
        var jsonBytes: Data?
        var binData: Data?
        while off + 8 <= data.count {
            let chunkLen = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: off, as: UInt32.self) }
            let chunkType = String(data: data.subdata(in: (off + 4)..<(off + 8)), encoding: .ascii)
            off += 8
            guard off + Int(chunkLen) <= data.count else { break }
            let chunk = data.subdata(in: off..<(off + Int(chunkLen)))
            off += Int(chunkLen)
            if chunkType == "JSON" { jsonBytes = chunk }
            else if chunkType == "BIN\u{0}" { binData = chunk }
        }
        guard let jb = jsonBytes else { throw GLBError.missingJSON }
        guard let obj = (try? JSONSerialization.jsonObject(with: jb)) as? [String: Any] else {
            throw GLBError.badJSON
        }
        guard let bd = binData else { throw GLBError.missingBIN }
        return (obj, bd)
    }

    // MARK: - 节点变换

    private static func localMatrix(_ node: [String: Any]) -> simd_float4x4 {
        if let m = node["matrix"] as? [Double], m.count == 16 {
            var mat = matrix_identity_float4x4
            // glTF matrix 为列主序 4×4；simd_float4x4.columns 是元组，
            // 不能用下标访问，须逐列赋值
            mat.columns.0 = SIMD4<Float>(Float(m[0]), Float(m[1]), Float(m[2]), Float(m[3]))
            mat.columns.1 = SIMD4<Float>(Float(m[4]), Float(m[5]), Float(m[6]), Float(m[7]))
            mat.columns.2 = SIMD4<Float>(Float(m[8]), Float(m[9]), Float(m[10]), Float(m[11]))
            mat.columns.3 = SIMD4<Float>(Float(m[12]), Float(m[13]), Float(m[14]), Float(m[15]))
            return mat
        }
        let t = node["translation"] as? [Double] ?? [0, 0, 0]
        let s = node["scale"] as? [Double] ?? [1, 1, 1]
        let r = node["rotation"] as? [Double] ?? [0, 0, 0, 1]
        let q = simd_quatf(ix: Float(r[0]), iy: Float(r[1]), iz: Float(r[2]), r: Float(r[3]))
        var mat = matrix_identity_float4x4
        mat.columns.3 = simd_float4(Float(t[0]), Float(t[1]), Float(t[2]), 1)
        let rot = simd_float4x4(q)
        let scl = simd_float4x4(columns: (
            simd_float4(Float(s[0]), 0, 0, 0),
            simd_float4(0, Float(s[1]), 0, 0),
            simd_float4(0, 0, Float(s[2]), 0),
            simd_float4(0, 0, 0, 1)))
        return mat * rot * scl   // glTF local = T * R * S
    }

    // MARK: - 访问器读取（含量化反量化）

    private static func componentCount(of type: String) -> Int {
        switch type {
        case "SCALAR": return 1
        case "VEC2": return 2
        case "VEC3": return 3
        case "VEC4": return 4
        case "MAT2": return 4
        case "MAT3": return 9
        case "MAT4": return 16
        default: return 3
        }
    }

    private static func componentSize(of componentType: Int) -> Int {
        switch componentType {
        case 5120, 5121: return 1    // BYTE / UBYTE
        case 5122, 5123: return 2    // SHORT / USHORT
        case 5125, 5126: return 4    // UINT / FLOAT
        default: return 4
        }
    }

    /// 读出访问器全部分量并反量化为 Float（flat 数组，count × numComponents）
    private static func readFloats(_ acc: Accessor, views: [BufferView], bin: Data) -> [Float] {
        var out: [Float] = []
        guard let bvi = acc.bufferView, bvi >= 0, bvi < views.count else { return out }
        let v = views[bvi]
        let nComp = componentCount(of: acc.type)
        let cSize = componentSize(of: acc.componentType)
        let elemSize = cSize * nComp
        let stride = v.byteStride > 0 ? v.byteStride : elemSize
        let base = v.byteOffset + acc.byteOffset
        guard acc.count > 0, base >= 0 else { return out }
        out.reserveCapacity(acc.count * nComp)
        bin.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<acc.count {
                let p = base + i * stride
                guard p + elemSize <= raw.count else { break }
                for c in 0..<nComp {
                    let o = p + c * cSize
                    let f: Float
                    switch acc.componentType {
                    case 5126:
                        f = raw.loadUnaligned(fromByteOffset: o, as: Float.self)
                    case 5122:
                        let s = raw.loadUnaligned(fromByteOffset: o, as: Int16.self)
                        f = acc.normalized ? max(Float(s) / 32767, -1) : Float(s)
                    case 5123:
                        let u = raw.loadUnaligned(fromByteOffset: o, as: UInt16.self)
                        f = acc.normalized ? Float(u) / 65535 : Float(u)
                    case 5120:
                        let s = raw.loadUnaligned(fromByteOffset: o, as: Int8.self)
                        f = acc.normalized ? max(Float(s) / 127, -1) : Float(s)
                    case 5121:
                        let u = raw.loadUnaligned(fromByteOffset: o, as: UInt8.self)
                        f = acc.normalized ? Float(u) / 255 : Float(u)
                    case 5125:
                        let u = raw.loadUnaligned(fromByteOffset: o, as: UInt32.self)
                        f = Float(u)
                    default:
                        f = 0
                    }
                    out.append(f)
                }
            }
        }
        return out
    }

    /// 索引读取（统一转 UInt32）
    private static func readIndices(_ acc: Accessor, views: [BufferView], bin: Data) -> [UInt32] {
        var out: [UInt32] = []
        guard let bvi = acc.bufferView, bvi >= 0, bvi < views.count else { return out }
        let v = views[bvi]
        let cSize = componentSize(of: acc.componentType)
        let stride = v.byteStride > 0 ? v.byteStride : cSize
        let base = v.byteOffset + acc.byteOffset
        guard acc.count > 0, base >= 0 else { return out }
        out.reserveCapacity(acc.count)
        bin.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for i in 0..<acc.count {
                let o = base + i * stride
                guard o + cSize <= raw.count else { break }
                let idx: UInt32
                switch acc.componentType {
                case 5121: idx = UInt32(raw.loadUnaligned(fromByteOffset: o, as: UInt8.self))
                case 5123: idx = UInt32(raw.loadUnaligned(fromByteOffset: o, as: UInt16.self))
                case 5125: idx = raw.loadUnaligned(fromByteOffset: o, as: UInt32.self)
                default:   idx = 0
                }
                out.append(idx)
            }
        }
        return out
    }

    // MARK: - 材质与贴图

    /// iOS 15–17 无 IBL 时把金属度压低，避免金属件渲染成黑块（与 .rk 管线策略一致）
    private static var hasImageBasedLight: Bool {
        if #available(iOS 18.0, *) { return true }
        return false
    }

    private static func makeMaterial(_ p: MatParams,
                                     textures: [Int: TextureResource],
                                     tint: SIMD4<Float>? = nil) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        var c = p.baseColor
        // 配色变体：整体乘色调（线性空间），贴图颜色 × tint
        if let tint {
            c = SIMD4<Float>(c.x * tint.x, c.y * tint.y, c.z * tint.z, c.w)
        }
        let lowerName = p.name.lowercased()
        let isGlass = lowerName.contains("glass") || lowerName.contains("window")
        var baseAlpha: CGFloat = 1
        if p.alphaMode == "BLEND" && p.textureIndex == nil {
            baseAlpha = isGlass ? 0.72 : 0.4
        } else {
            baseAlpha = CGFloat(c.w)
        }
        let tint = UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: baseAlpha)
        m.baseColor = .init(tint: tint)
        var metallic = p.metallic
        var roughness = p.roughness
        if !hasImageBasedLight, metallic > 0.3 {
            metallic = 0.25
            roughness = min(1.0, roughness * 1.4 + 0.12)
        }
        m.metallic = .init(floatLiteral: metallic)
        m.roughness = .init(floatLiteral: roughness)
        // 车漆类材质加一层薄清漆（与 .rk 管线一致，影棚级高光）
        let isPaintLike = lowerName.contains("carpaint") || lowerName.contains("car_paint")
            || lowerName.contains("cp_m") || lowerName.contains("paint")
        if isPaintLike {
            m.clearcoat = 0.9
            m.clearcoatRoughness = 0.06
        }
        if let ti = p.textureIndex, let tex = textures[ti] {
            m.baseColor.texture = .init(tex)
        }
        if p.alphaMode == "BLEND" {
            m.blending = .transparent(opacity: 1.0)
        }
        if p.doubleSided { m.faceCulling = .none }
        return m
    }

    /// image 字节（WebP/PNG/JPEG）→ TextureResource
    ///
    /// 走「CGImage → PNG 临时文件 → TextureResource.load(contentsOf:)」：
    /// iOS 26 SDK 移除了 generate(from:) 旧重载（新签名要求 semantic 参数），
    /// 而 load(contentsOf:) 与 .rk 管线同款，全 SDK 版本稳定可用。
    private static func makeTexture(from bytes: Data) -> TextureResource? {
        guard let src = CGImageSourceCreateWithData(bytes as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        guard let png = UIImage(cgImage: cg).pngData() else { return nil }
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("glb_tex_\(UUID().uuidString).png")
        do {
            try png.write(to: url)
        } catch {
            return nil
        }
        defer { try? FileManager.default.removeItem(at: url) }
        return try? TextureResource.load(contentsOf: url)
    }

    // MARK: - 几何兜底

    /// 缺 NORMAL 的 primitive：按面法线面积加权平均补算平滑法线
    private static func computeSmoothNormals(positions: [SIMD3<Float>],
                                             indices: [UInt32]) -> [SIMD3<Float>] {
        var normals = [SIMD3<Float>](repeating: .zero, count: positions.count)
        var i = 0
        while i + 2 < indices.count {
            let a = positions[Int(indices[i])]
            let b = positions[Int(indices[i + 1])]
            let c = positions[Int(indices[i + 2])]
            let n = simd_cross(b - a, c - a)
            normals[Int(indices[i])] += n
            normals[Int(indices[i + 1])] += n
            normals[Int(indices[i + 2])] += n
            i += 3
        }
        for k in normals.indices {
            normals[k] = simd_length(normals[k]) > 1e-9 ? simd_normalize(normals[k]) : SIMD3<Float>(0, 1, 0)
        }
        return normals
    }
}
