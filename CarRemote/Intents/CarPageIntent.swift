import AppIntents
import Foundation

// MARK: - 打开 App 指定页面（查看类）

/// CAKOCHE 的三个页面：车（3D 车模 + 车况）、空调、我的。
@available(iOS 16.0, *)
enum CakochePageOption: String, AppEnum, CaseIterable, Sendable {
    case home
    case climate
    case mine

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "页面")
    }

    static var caseDisplayRepresentations: [CakochePageOption: DisplayRepresentation] {
        [
            .home: DisplayRepresentation(title: "车辆首页", image: DisplayRepresentation.Image(systemName: "car.fill")),
            .climate: DisplayRepresentation(title: "空调", image: DisplayRepresentation.Image(systemName: "snowflake")),
            .mine: DisplayRepresentation(title: "我的", image: DisplayRepresentation.Image(systemName: "person"))
        ]
    }
}

/// 页面跳转的落地位置。
///
/// Intent 与 App 在同一个进程（后台被唤起后由系统拉起 App），
/// 因此用 `UserDefaults.standard` 传一个「待跳转页面」标记即可，
/// App 回到前台时取走并清掉，不会重复跳转。
enum CakochePendingPage {
    static let key = "cakoche.pendingPage"

    static func set(_ raw: String) {
        UserDefaults.standard.set(raw, forKey: key)
    }

    /// 取走待跳转页面（读完即清空）
    static func consume() -> String? {
        let value = UserDefaults.standard.string(forKey: key)
        if value != nil { UserDefaults.standard.removeObject(forKey: key) }
        return value
    }
}

/// 「打开 App 页面」：适合放在锁屏 / 桌面，一按直达空调面板，省掉三次滑动。
@available(iOS 16.0, *)
struct OpenCakochePageIntent: AppIntent {
    static var title: LocalizedStringResource = "打开 App 页面"
    static var description: IntentDescription = "直接打开 CAKOCHE 的车辆首页、空调面板或我的页面"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "页面")
    var page: CakochePageOption

    init() {}

    init(page: CakochePageOption) {
        self.page = page
    }

    static var parameterSummary: some ParameterSummary {
        Summary("打开 \(\.$page)")
    }

    func perform() async throws -> some IntentResult {
        CakochePendingPage.set(page.rawValue)
        return .result()
    }
}
