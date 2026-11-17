import Foundation

/// 长安控车正式版全系 14 款官方 GLB 车模（1.11.4）。
/// 与 CAKOCHE 同源，均为带 Int_P 内饰节点的真 3D 模型，来自「我的爱车」/岁岁长安 v5.17。
/// 用于「3D 车模库」与首页车模浏览，让全部内置车模都可切换查看（不再只有 2D 对应的几款）。
#if !CAKOCHE
public struct FormalCarModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let glb: String      // 实际资源名（不含 .glb 扩展）
    public let group: String

    public init(_ id: String, _ name: String, _ group: String, glb: String? = nil) {
        self.id = id
        self.name = name
        self.group = group
        self.glb = glb ?? id
    }

    public var model3DName: String { "\(glb).glb" }
}

public enum FormalCarModels {
    /// 全部 14 款，顺序与 CAKOCHE 全系一致。
    public static let all: [FormalCarModel] = [
        .init("c211",         "逸动 PLUS",           "轿车"),
        .init("c236",         "深蓝 SL03",           "新能源"),
        .init("c281",         "UNI-V",               "轿车"),
        .init("c281phev",     "UNI-V 智电 iDD",      "新能源"),
        .init("c589",         "逸达 / 三代逸动",      "轿车"),
        .init("c589phev",     "逸达 iDD",            "新能源"),
        .init("cd569",        "UNI-K",               "SUV"),
        .init("s202",         "UNI-T",               "SUV"),
        .init("s203",         "CS55 PLUS",           "SUV"),
        .init("s203phev",     "CS55 PLUS 智电",      "新能源"),
        .init("s311",         "CS75 PLUS 二代",      "SUV"),
        .init("s311mca",      "CS75 PLUS 改款",      "SUV"),
        .init("s311mca1phev", "CS75 PLUS 三代 iDD",  "新能源"),
        .init("s311phev",     "CS75 PLUS iDD",       "新能源")
    ]

    /// 当前选中的车模 id（正式版车模库独立记忆，不覆盖「切换车型」的业务车型）。
    private static let key = "formalGallery.selectedModel"
    public static var selectedID: String {
        get {
            let saved = UserDefaults.standard.string(forKey: key) ?? ""
            return all.contains { $0.id == saved } ? saved : "c211"
        }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    public static var selected: FormalCarModel {
        all.first { $0.id == selectedID } ?? all[0]
    }
}
#endif
