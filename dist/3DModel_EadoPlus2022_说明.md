# 逸动PLUS 3D 车模资源包（.rk 格式）

本包是「长安控车」iOS App 内置的 **逸动PLUS 2022（C211）官方 3D 车模**，从长安智慧云控安装包中的官方 glb 离线转换而来，可直接用于你的网站（Web 端渲染）。

## 一、包内文件

```
3DModel_EadoPlus2022/
├── EadoPlus2022.rk.json        # 白色车 清单（材质/部件/分组/动画）
├── EadoPlus2022.rk.bin         # 白色车 几何数据（Float32 pos/nor/uv + UInt32 idx）
├── EadoPlus2022Gray.rk.json    # 灰色车 清单（几何复用上面同一个 .rk.bin）
└── tex/
    ├── tex_0.png ~ tex_8.png   # 贴图（PNG，1024×1024 左右）
```

`.rk.json` 里 `geometryFile` 字段指向对应的 `.rk.bin`，灰色车也指向 `EadoPlus2022.rk.bin`（两个车型共享同一套网格，只换车漆颜色）。

## 二、.rk 格式规范

### 1. 清单 `*.rk.json`

顶层字段：

| 字段 | 说明 |
|---|---|
| `format` | 固定字符串 `CarRemote-RK-1` |
| `geometryFile` | 几何二进制文件名（同目录） |
| `materials` | 材质数组 |
| `parts` | 部件数组（每个部件引用一个材质 + 一段几何区间） |
| `groups` | 分组（可动部件的父节点与初始变换） |

**materials[i]**：

| 字段 | 说明 |
|---|---|
| `name` | 材质名（App 内按名字做逻辑映射，如车漆/玻璃/大灯） |
| `texture` | 贴图文件名（相对 `tex/` 目录），无贴图则 `null` |
| `baseColorSRGB` | `[r,g,b,a]`，0–1 |
| `metallic` | 金属度 0–1 |
| `roughness` | 粗糙度 0–1 |
| `emissiveSRGB` | 自发光色（灯件用），无则 `null` |
| `blend` | 是否透明混合（玻璃、灯罩） |
| `doubleSided` | 是否双面 |

**parts[i]**：

| 字段 | 说明 |
|---|---|
| `name` | 部件名 |
| `group` | 所属分组名（`static` / `doorFL` / `windowFR` / `wheelFL` / `trunk` …） |
| `material` | 材质索引（`materials` 数组下标） |
| `vertexCount` / `indexCount` | 顶点数 / 索引数 |
| `positionOffset` | 顶点数据起始偏移（字节） |
| `normalOffset` | 法线数据起始偏移（字节） |
| `uvOffset` | UV 数据起始偏移（字节） |
| `indexOffset` | 索引数据起始偏移（字节） |
| `hasNormal` / `hasUV` | 是否带法线 / UV |
| `isLight` | 是否为灯件（用于开灯逻辑） |

**groups[name]**：`position`（xyz 平移）、`rotation`（xyzw 四元数）、`parent`（父分组）。

### 2. 几何 `*.rk.bin`

小端序连续数据块，按 `parts` 里各偏移量切片：

- 顶点：3 × Float32（position），3 × Float32（normal），2 × Float32（uv）
- 索引：UInt32 三角形索引

## 三、渲染要点（照抄 App 里的做法，否则会和 App 效果不一致）

1. **车漆必须 metal = 0**。`C211_CarPaint` 的 metallic 是 0，roughness 0.28。若把 metallic 设成 1 而环境贴图（IBL）缺失，车身会渲染成**纯黑块**。
2. **加 clearcoat 清漆层**：`clearcoat = 0.9`、`clearcoatRoughness = 0.06`（three.js 里对应 `clearcoat` / `clearcoatRoughness`，或 `MeshPhysicalMaterial`）。
3. **玻璃透明度**：`C211_WindowGlass` 是 blend 材质，基色 `[0.13, 0.14, 0.16]`，透明度建议 0.72，太低会变成"透明片"看不清深色玻璃。
4. **环境光**：App 用 `EnvironmentResource` 生成程序化影棚环境图（iOS 18+ API），Web 端建议直接用一张 HDR 环境贴图（`scene.environment`），并配 `environmentIntensity ≈ 0.8`。没有 IBL 时车漆会显得很平。
5. **灯位**：key(强度 1600) + fill(500，冷色) + rim(900，暖色轮廓光) + bounce(220，地面反光) 四灯位，是"看起来像影棚棚拍"的关键。
6. **灯件默认隐藏**，仅在对应状态下点亮：
   - `C211_Light_HL_LOn` / `C281_Light_DRL_LOn` → 大灯 / 日行灯
   - `C211_Light_TL_LOn` → 尾灯
   - `C211_Light_BL_LOn` → 刹车灯
   - 其余 `C211_Light_*`（门迎宾灯等）**不要点亮**——App 里就是因此出现过"车身两侧多出两块光"的 bug。
7. **车门/车窗/把手/车轮分组**已有独立分组，可直接做开合动画：
   `doorFL/doorFR/doorBL/doorBR`、`windowFL/windowFR/windowBL/windowBR`、`handleFL/...`、`wheelFL/wheelFR/wheelBL/wheelBR`、`trunk`、`sunroof`。

## 四、灰色变体

`EadoPlus2022Gray.rk.json` 与白色车唯一的差别是车漆基色：

- `C211_CarPaint` / `C211_RedCarPaint`：`[0.30, 0.31, 0.325, 1.0]`（深灰，贴近实车观感）
- 白色车：`C211_CarPaint` = `[1, 1, 1, 1.0]`

两者共用 `EadoPlus2022.rk.bin`，所以文件很小（几何 6MB + 贴图 1MB）。
