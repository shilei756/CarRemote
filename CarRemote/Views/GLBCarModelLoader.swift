//
//  GLBCarModelLoader.swift
//  长安控车 — 「我的爱车」GLB 车模零依赖解析器
//
//  资产来源：从「我的爱车」App（com.kancher.kc2026）提取的 12 款长安系 3D 车模
//  （GLB 2.0 格式），已离线预处理：meshopt 压缩已解码还原、动画已剔除、
//  贴图保留 WebP（iOS 14+ ImageIO 原生解码）、顶点保留量化 SHORT/BYTE
//  （本解析器原生反量化），因此单模型体积控制在 2~6MB。
//
//  解析产物：与 Car3DView 现有 .rk 管线同一结构（RKCarModel），
//  门/窗/灯/轮字典为空 —— 即「仅查看旋转」的静态车模，
//  完整复用轨道相机（滑动/捏合/双击/自动取景）与挂载系统。
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
    static func load(named name: String) -> RKCarModel? {
        guard let url = resourceURL(named: name, ext: "glb"),
              let data = try? Data(contentsOf: url) else { return nil }
        return build(from: data)
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

    static func build(from data: Data) -> RKCarModel? {
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

            // ---- 几何：遍历节点树，烘焙世界变换 ----
            let carRoot = Entity()
            carRoot.name = "carRoot_glb"

            var worldMatrices = [simd_float4x4](repeating: matrix_identity_float4x4,
                                                count: max(nodesJSON.count, 1))
            var accessorFloatCache: [Int: [Float]] = [:]
            var accessorIndexCache: [Int: [UInt32]] = [:]
            var materialCache: [Int: PhysicallyBasedMaterial] = [:]
            /// 已烘焙世界变换的 POSITION 顶点缓存（key = accessor 序号），供取景代表点二次扫描
            var bakedPositions: [Int: [SIMD3<Float>]] = [:]

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
            if let sceneIdx = (json["scene"] as? Int) ?? 0, sceneIdx < scenesJSON.count,
               let rn = scenesJSON[sceneIdx]["nodes"] as? [Int] {
                rootNodes = rn
            } else {
                rootNodes = Array(0..<nodesJSON.count)
            }
            for r in rootNodes where r < nodesJSON.count {
                _ = worldMatrix(node: r, parent: matrix_identity_float4x4)
            }

            var primitiveCounter = 0
            for (ni, node) in nodesJSON.enumerated() {
                guard let meshIdx = node["mesh"] as? Int, meshIdx < meshes.count else { continue }
                let world = worldMatrices[ni]
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
                    // 三角形数量取整 + 越界剔除
                    if indices.count % 3 != 0 { indices.removeLast(indices.count % 3) }
                    indices = indices.filter { Int($0) < vc }
                    guard indices.count >= 3 else { continue }

                    // 烘焙世界变换
                    var positions = [SIMD3<Float>](repeating: .zero, count: vc)
                    let col0 = world.columns.0, col1 = world.columns.1
                    let col2 = world.columns.2, col3 = world.columns.3
                    for i in 0..<vc {
                        let x = posFlat[i * 3], y = posFlat[i * 3 + 1], z = posFlat[i * 3 + 2]
                        let wx = col0.x * x + col1.x * y + col2.x * z + col3.x
                        let wy = col0.y * x + col1.y * y + col2.y * z + col3.y
                        let wz = col0.z * x + col1.z * y + col2.z * z + col3.z
                        positions[i] = SIMD3<Float>(wx, wy, wz)
                        boundsMin.x = min(boundsMin.x, wx); boundsMax.x = max(boundsMax.x, wx)
                        boundsMin.y = min(boundsMin.y, wy); boundsMax.y = max(boundsMax.y, wy)
                        boundsMin.z = min(boundsMin.z, wz); boundsMax.z = max(boundsMax.z, wz)
                    }
                    // 多个 primitive 常共享同一 POSITION accessor（同一大网格分材质），
                    // 只需缓存一份供取景扫描
                    if bakedPositions[posIdx] == nil {
                        bakedPositions[posIdx] = positions
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
                        mat = makeMaterial(params, textures: imageTextures)
                        materialCache[matIdx] = mat
                    }

                    // 构建网格
                    var descriptor = MeshDescriptor(name: "glb_p\(primitiveCounter)")
                    primitiveCounter += 1
                    descriptor.positions = MeshBuffers.Positions(positions)
                    if let normals { descriptor.normals = MeshBuffers.Normals(normals) }
                    if let uvs { descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uvs) }
                    descriptor.primitives = .triangles(indices)
                    descriptor.materials = .allFaces(0)
                    guard let mesh = try? MeshResource.generate(from: [descriptor]) else { continue }
                    let model = ModelEntity(mesh: mesh, materials: [mat])
                    carRoot.addChild(model)
                }
            }
            guard primitiveCounter > 0 else { return nil }

            // ---- 取景代表点（与 .rk 管线一致：方位角 × 高度分格取半径最大顶点）----
            guard boundsMin.x <= boundsMax.x else { return nil }
            let fitCenter = (boundsMin + boundsMax) / 2
            let ySpan = max(boundsMax.y - boundsMin.y, 1e-5)
            func recordFit(_ p: SIMD3<Float>) {
                let rel = p - fitCenter
                let azf = atan2(rel.x, rel.z)
                var bi = Int((azf + .pi) / (2 * .pi) * Float(fitBuckets))
                bi = min(max(bi, 0), fitBuckets - 1)
                var li = Int((p.y - boundsMin.y) / ySpan * Float(fitLayers))
                li = min(max(li, 0), fitLayers - 1)
                let k = bi * fitLayers + li
                let r2 = simd_dot(rel, rel)
                if r2 > fitBest[k] { fitBest[k] = r2; fitReps[k] = p }
            }
            // 遍历已烘焙的 POSITION 顶点补代表点（二遍扫描，与 .rk 管线一致）
            for (_, verts) in bakedPositions {
                for p in verts { recordFit(p) }
            }
            var fitPoints: [SIMD3<Float>] = []
            fitPoints.reserveCapacity(fitBuckets * fitLayers)
            for k in 0..<(fitBuckets * fitLayers) where fitBest[k] >= 0 {
                fitPoints.append(fitReps[k])
            }

            return RKCarModel(root: carRoot,
                              partEntities: [:], windowEntities: [:], handleEntities: [:],
                              wheelEntities: [:], uniqueWheels: [], lightEntities: [:],
                              doorTilt: [:], sunroofRest: .zero, sunroofOpen: .zero,
                              sunroofTilt: 0, windowRest: [:], windowOpen: [:],
                              windowTilt: [:], handleTilt: [:],
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
            for c in 0..<4 {
                for r in 0..<4 {
                    mat.columns[c][r] = Float(m[c * 4 + r])   // glTF 列主序
                }
            }
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
                                     textures: [Int: TextureResource]) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        let c = p.baseColor
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
    private static func makeTexture(from bytes: Data) -> TextureResource? {
        guard let src = CGImageSourceCreateWithData(bytes as CFData, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        return try? TextureResource.generate(from: cg, withName: "glb_tex",
                                             options: [.generateMipmaps])
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
