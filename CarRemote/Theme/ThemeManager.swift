import SwiftUI
import CarCore

/// 全局主题管理（浅色 / 夜间）。
///
/// 1.10.0：这里只负责保存「用户意愿」并触发视图树重绘，
/// 真正的深浅色统一由 `AppearanceRoot.preferredColorScheme` 下发：
///  - 开关【开】→ 不干预 colorScheme，完全跟随手机系统深浅；
///  - 开关【关】→ 强制浅色，连 TabBar / Form / 系统语义色一起压成浅色。
/// 配色本身由 `WebTheme` 的 UIKit 动态色跟随 trait 自动重解析，
/// 不再需要「手动同步系统深浅 → 写 UserDefaults → 靠重绘刷新静态色」这条脆弱链路。
@MainActor
final class ThemeManager: ObservableObject {

    static let shared = ThemeManager()

    @Published var theme: AppTheme {
        didSet { SharedStore.saveAppTheme(theme) }
    }

    private init() {
        theme = SharedStore.loadAppTheme()
    }

    /// 实际生效的深色状态（供设置页文案等使用；是否深色最终以视图树 trait 为准）
    var isDark: Bool { theme == .dark }

    func set(_ newTheme: AppTheme) {
        theme = newTheme
    }

    func toggle() {
        theme = theme == .light ? .dark : .light
    }
}
