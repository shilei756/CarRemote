import WidgetKit
import SwiftUI

/// 桌面小组件入口：锁屏 + 主屏多种尺寸 + 锁屏快捷控车
/// 1.9.0：小组件扩展部署目标下探到 iOS 16。
@main
struct CarWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarRemoteWidget()
        CarQuickControlWidget()
    }
}

/// `containerBackground(for: .widget)` 是 iOS 17 才有的 API。
/// iOS 16 上退回普通 `.background`，保证同一套视图在两个系统版本都能编译、显示。
private struct WidgetContainerBackground: ViewModifier {
    let color: Color
    @Environment(\.widgetFamily) private var family

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            content.containerBackground(for: .widget) { color }
        } else {
            // iOS 16 锁屏 accessory 必须保持透明（否则会出现白底方块）；
            // 主屏 system* 家族才补一层可读背景。
            content.background(isAccessory ? Color.clear : color)
        }
    }

    private var isAccessory: Bool {
        family == .accessoryCircular || family == .accessoryRectangular || family == .accessoryInline
    }
}

private extension View {
    func widgetContainerBackground(_ color: Color) -> some View {
        modifier(WidgetContainerBackground(color: color))
    }
}

/// 主小组件（systemSmall / Medium / Large + 锁屏 accessoryCircular / accessoryRectangular）
/// accessoryCircular / accessoryRectangular 从 iOS 16 起就有，无需降级处理。
struct CarRemoteWidget: Widget {
    let kind: String = "CarRemoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CarWidgetProvider()) { entry in
            CarWidgetEntryView(entry: entry)
                .widgetContainerBackground(Color(.systemBackground))
        }
        .configurationDisplayName("长安控车")
        .description("车况一览与快捷控车：续航、油量、胎压、锁态，一键开锁/闭锁/闪灯/鸣笛。")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular
        ])
    }
}

/// 锁屏快捷控车小组件：
/// - iOS 17+：交互式按钮，不解锁手机直接执行；
/// - iOS 16：点按打开 App 并弹确认框，确认后执行同一条指令（功能不缺失）。
/// - 免签/巨魔环境：在「快捷指令」里运行「小组件独立登录」绑定账号，
///   凭据存小组件沙盒，绑定一次全部小组件（主屏+锁屏）生效
struct CarQuickControlWidget: Widget {
    let kind: String = "CarQuickControlWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CarWidgetProvider()) { entry in
            QuickControlEntryView(entry: entry)
                .widgetContainerBackground(Color.clear)
        }
        .configurationDisplayName("快捷控车")
        .description("开关车门锁、点火/熄火、寻车。iOS 17 及以上锁屏可直接控车；iOS 16 点按后在 App 内确认执行。免签/巨魔安装请用「快捷指令」运行「小组件独立登录」绑定。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
