import Foundation

/// CAKOCHE 全系 12 款长安官方 GLB 车模（含从 git 历史 f016ee0 恢复的 7 款）。
/// 车模资产与正式版「我的爱车」同源，均为带 Int_P 内饰节点的真 3D 模型。
struct CakocheModel: Identifiable, Hashable {
    let id: String
    let name: String
    let glb: String
    let group: String
    /// 内饰是否完整分件（false = 借用 c211 白逸动完整座舱看内饰）
    let fullInterior: Bool

    init(_ id: String, _ name: String, _ group: String, fullInterior: Bool = false) {
        self.id = id
        self.name = name
        self.glb = id + ".glb"
        self.group = group
        self.fullInterior = fullInterior
    }
}

enum CakocheModels {
    static let all: [CakocheModel] = [
        .init("c211",        "逸动 PLUS",           "轿车",   fullInterior: true),
        .init("c589",        "逸达 / 三代逸动",      "轿车"),
        .init("c281",        "UNI-V",               "轿车"),
        .init("c281phev",    "UNI-V 智电 iDD",      "新能源"),
        .init("s311",        "CS75 PLUS 二代",      "SUV",    fullInterior: true),
        .init("s311mca",     "CS75 PLUS 改款",      "SUV"),
        .init("s311mca1phev","CS75 PLUS 三代 iDD",  "新能源"),
        .init("s203",        "CS55 PLUS",           "SUV"),
        .init("s203phev",    "CS55 PLUS 智电",      "新能源"),
        .init("s202",        "UNI-T",               "SUV"),
        .init("cd569",       "UNI-K",               "SUV"),
        .init("c236",        "深蓝 SL03",           "新能源")
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
}
