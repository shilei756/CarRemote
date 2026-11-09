import SwiftUI
import CarCore

/// 全局主题管理（浅色 / 夜间，对应网页版夜间模式开关）
///
/// 1.9.0：夜间模式改为跟随手机系统外观。
/// - App 内「夜间模式」只记录用户意愿；
/// - 只有手机也处于深色模式时深色界面才生效；
/// - 手机切回浅色，`systemIsDark` 变化会触发整棵视图树重算配色，
///   无需用户再去 App 里手动关开关。
@MainActor
final class ThemeManager: ObservableObject {

    static let shared = ThemeManager()

    @Published var theme: AppTheme {
        didSet { SharedStore.saveAppTheme(theme) }
    }

    /// 手机系统是否为深色（由 RootView 的 colorScheme 同步）
    @Published private(set) var systemIsDark: Bool

    private init() {
        theme = SharedStore.loadAppTheme()
        systemIsDark = SharedStore.systemIsDark
    }

    /// 实际生效的深色状态
    var isDark: Bool { theme == .dark && systemIsDark }

    func set(_ newTheme: AppTheme) {
        theme = newTheme
    }

    func toggle() {
        theme = theme == .light ? .dark : .light
    }

    /// 系统深浅变化：先持久化（供 WebTheme 静态色值读取），再触发重绘
    func syncSystem(isDark: Bool) {
        SharedStore.systemIsDark = isDark
        if systemIsDark != isDark {
            systemIsDark = isDark
        }
    }
}
