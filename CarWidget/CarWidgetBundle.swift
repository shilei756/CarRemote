import WidgetKit
import SwiftUI

/// 桌面小组件入口：锁屏 + 主屏多种尺寸
@main
struct CarWidgetBundle: WidgetBundle {
    var body: some Widget {
        CarRemoteWidget()
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
        .configurationDisplayName("远程控车")
        .description("车况一览与快捷控车：续航、油量、胎压、锁态，一键开锁/闭锁/闪灯/鸣笛。")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            .accessoryCircular, .accessoryRectangular
        ])
    }
}
