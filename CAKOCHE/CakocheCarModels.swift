import Foundation

/// CAKOCHE 全系 14 款长安官方 GLB 车模（含从 git 历史 f016ee0 恢复的款）。
/// 车模资产与正式版「我的爱车」同源，均为带 Int_P 内饰节点的真 3D 模型。
/// 1.2.7 起：车模换成「岁岁长安 v5.17」的精细版（带 14 段车身动画，节点枢轴兼容），
/// 新增逸达 iDD(c589phev) 与 CS75 PLUS iDD(s311phev)。
struct CakocheModel: Identifiable, Hashable {
    let id: String
    let name: String
    let glb: String
    let group: String
    /// 内饰是否完整分件（false = 借用 c211 白逸动完整座舱看内饰）
    let fullInterior: Bool
    /// 1.2.2：油箱容积（L），参考网页版 CAR_MODELS.tank。
    /// 油量条按所选车型的油箱容积换算，剩余升数仍取网站实时车况。
    let tankL: Double

    init(_ id: String, _ name: String, _ group: String, _ tankL: Double,
         fullInterior: Bool = false) {
        self.id = id
        self.name = name
        self.glb = id + ".glb"
        self.group = group
        self.fullInterior = fullInterior
        self.tankL = tankL
    }
}

enum CakocheModels {
    /// 油箱容积对照（长安官网参数 / 网页版 CAR_MODELS.tank）：
    ///   逸动 PLUS 53 · 三代逸动·逸达 53 · UNI-V 51 · UNI-V iDD 45
    ///   CS75 PLUS 全系 58 · CS55 PLUS 55 · UNI-T 55 · UNI-K 56 · 深蓝 SL03 增程 45
    static let all: [CakocheModel] = [
        .init("c211",        "逸动 PLUS",           "轿车",   53, fullInterior: true),
        .init("c589",        "逸达 / 三代逸动",      "轿车",   53),
        .init("c589phev",    "逸达 iDD",            "新能源", 45),
        .init("c281",        "UNI-V",               "轿车",   51),
        .init("c281phev",    "UNI-V 智电 iDD",      "新能源", 45),
        .init("s311",        "CS75 PLUS 二代",      "SUV",    58, fullInterior: true),
        .init("s311mca",     "CS75 PLUS 改款",      "SUV",    58),
        .init("s311phev",    "CS75 PLUS iDD",       "新能源", 58),
        .init("s311mca1phev","CS75 PLUS 三代 iDD",  "新能源", 58),
        .init("s203",        "CS55 PLUS",           "SUV",    55),
        .init("s203phev",    "CS55 PLUS 智电",      "新能源", 55),
        .init("s202",        "UNI-T",               "SUV",    55),
        .init("cd569",       "UNI-K",               "SUV",    56),
        .init("c236",        "深蓝 SL03",           "新能源", 45)
    ]

    private static let key = "cakoche.selectedModel"

    static var selectedID: String {
        get {
            let saved = UserDefaults.standard.string(forKey: key) ?? ""
            return all.contains { $0.id == saved } ? saved : "c211"
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var selected: CakocheModel {
        all.first { $0.id == selectedID } ?? all[0]
    }

    /// 座舱模型：只有完整分件座舱的车型用自己，其余统一借白逸动 c211 完整内饰。
    static func cockpitGLB(for model: CakocheModel) -> String {
        model.fullInterior ? model.glb : "c211.glb"
    }

    // MARK: - 车架号自动识别（1.2.7，复刻「岁岁长安」网页版 detectModelKey）

    /// 自动识别开关：true=按车架号 seriesCode 自动切车模；false=用户手选，刷新不覆盖。
    private static let autoKey = "cakoche.modelAuto"
    static var modelAuto: Bool {
        get { UserDefaults.standard.object(forKey: autoKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoKey) }
    }

    /// 自动选中车型时发出的通知（object 为车型 id），供首页同步本地状态。
    static let didAutoSelect = Notification.Name("cakoche.didAutoSelect")

    /// 网页版车型 key → 我们的 id。seriesCode 折算后先查此表。
    /// 覆盖全部 14 款：主码 + `_P` 插混变体。
    private static let alias: [String: String] = [
        "c211": "c211",
        "c236": "c236",
        "c281": "c281", "c281_p": "c281phev",
        "c589": "c589", "c589_p": "c589phev",
        "cd569": "cd569",
        "s202": "s202",
        "s203": "s203", "s203_p": "s203phev",
        "s311": "s311", "s311_p": "s311phev",
        "s311mca": "s311mca"
    ]

    /// 把车架号系列码折算成车型 id。
    /// 复刻网页版：归一化 → 精确匹配 → 最长前缀。
    /// 支持 C211-1 / S311MCA-1 / C281-P / C589_P 等写法。
    static func detectModelKey(_ seriesCode: String?) -> String? {
        guard let sc = seriesCode, !sc.isEmpty else { return nil }
        let raw = sc.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [
            raw.replacingOccurrences(of: "-", with: "_"),          // C281-P -> c281_p
            raw.replacingOccurrences(of: "[_-]", with: "", options: .regularExpression),
            raw.split(separator: "-").first.map(String.init) ?? "", // S311MCA-1 -> s311mca
            raw
        ]
        // 1) 精确匹配
        for c in candidates {
            if let id = alias[c] { return id }
        }
        // 2) 最长前缀匹配（如 c281phev 命中 c281_p 之类）
        var best: (len: Int, id: String)?
        for (key, id) in alias {
            for c in candidates where c.hasPrefix(key) && key.count > (best?.len ?? 0) {
                best = (key.count, id)
            }
        }
        return best?.id
    }

    /// 车况刷新后调用：自动模式下、识别成功、且车型变化时切换。
    /// 用户手选（modelAuto=false）时完全不介入。
    static func applyAutoModelIfNeeded(seriesCode: String?) {
        guard modelAuto,
              let code = seriesCode,
              let id = detectModelKey(code),
              all.contains(where: { $0.id == id }),
              selectedID != id else { return }
        selectedID = id
        NotificationCenter.default.post(name: didAutoSelect, object: id)
    }

    /// 立即按当前车况应用一次（设置页点「自动识别」时用）。
    static func applyAutoNow(seriesCode: String?) {
        modelAuto = true
        applyAutoModelIfNeeded(seriesCode: seriesCode)
    }
}
