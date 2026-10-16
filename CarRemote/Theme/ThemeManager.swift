import SwiftUI
import CarCore

/// 全局主题管理（浅色 / 夜间，对应网页版夜间模式开关）
@MainActor
final class ThemeManager: ObservableObject {

    static let shared = ThemeManager()

    @Published var theme: AppTheme {
        didSet { SharedStore.saveAppTheme(theme) }
    }

    private init() {
        theme = SharedStore.loadAppTheme()
    }

    var isDark: Bool { theme == .dark }

    func set(_ newTheme: AppTheme) {
        theme = newTheme
    }

    func toggle() {
        theme = theme == .light ? .dark : .light
    }
}
