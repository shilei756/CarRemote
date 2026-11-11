import WidgetKit
import SwiftUI

/// CAKOCHE 小组件 Bundle：点阵风格车况 + 快捷控车。
/// 与 CAKOCHE App 共用 SharedStore 快照通道；免签/巨魔环境自动回退小组件本地沙盒。
@main
struct CakocheWidgetBundle: WidgetBundle {
    var body: some Widget {
        CakocheStatusWidget()
    }
}
