import WidgetKit
import SwiftUI
import CarCore

/// 小组件数据：车况快照（由主 App 刷新时写入 App Group）
struct CarStatusEntry: TimelineEntry {
    let date: Date
    let snapshot: StatusSnapshot?

    /// 占位示例数据（仅在 SwiftUI 预览 / 编辑态使用）
    static var placeholder: CarStatusEntry {
        CarStatusEntry(date: Date(), snapshot: nil)
    }
}

/// 时间线提供器：主 App 每次刷新车况都会 reloadAllTimelines，
/// 这里兜底 30 分钟自动刷新一次，保证时间显示不会太旧。
struct CarWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> CarStatusEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (CarStatusEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CarStatusEntry>) -> Void) {
        let entry = makeEntry()
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
    }

    private func makeEntry() -> CarStatusEntry {
        CarStatusEntry(date: Date(), snapshot: SharedStore.loadStatusSnapshot())
    }
}
