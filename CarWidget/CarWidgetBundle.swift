import WidgetKit
import SwiftUI

/// 桌面小组件入口：锁屏 + 主屏多种尺寸 + 锁屏快捷控车
@main
struct CarWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarRemoteWidget()
        CarQuickControlWidget()
    }
}

/// 主小组件（systemSmall / Medium / Large + 锁屏 accessoryCircular / accessoryRectangular）
struct CarRemoteWidget: Widget {
    let kind: String = "CarRemoteWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CarWidgetProvider()) { entry in
            CarWidgetEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(.systemBackground)
                }
        }
        .configurationDisplayName("长安控车")
        .description("车况一览与快捷控车：续航、油量、胎压、锁态，一键开锁/闭锁/闪灯/鸣笛。")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular
        ])
    }
}

/// 锁屏快捷控车小组件（iOS 17 交互式，不解锁手机直接执行）：
/// - 圆形：大锁钮，点按智能反向开关车门锁
/// - 矩形：开关锁 / 点火熄火 / 寻车 三按钮
struct CarQuickControlWidget: Widget {
    let kind: String = "CarQuickControlWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CarWidgetProvider()) { entry in
            QuickControlEntryView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("快捷控车")
        .description("不解锁手机直接控车：开关车门锁、点火/熄火、寻车。")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular])
    }
}
