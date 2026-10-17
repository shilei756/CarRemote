import WidgetKit
import SwiftUI
import CarCore

/// 小组件时间线条目：车况快照 + 用户自定义的 5 个控车按钮 + 车型外观
struct CarStatusEntry: TimelineEntry {
    var date: Date
    let snapshot: StatusSnapshot?
    let widgetCommands: [String]
    let carStyle: CarModelStyle
    let isLoggedIn: Bool

    static var placeholder: CarStatusEntry {
        CarStatusEntry(date: Date(), snapshot: nil,
                       widgetCommands: CarModelStyle.defaultWidgetCommands,
                       carStyle: .sedan, isLoggedIn: true)
    }
}

/// 时间线提供器：
/// - 主 App 每次刷新车况都会 reloadAllTimelines，即时更新；
/// - 这里兜底：时间线刷新时在小组件进程内直接拉一次官网车况
///   （凭据来自 App Group 共享存储，每人只有自己账号的），失败退回本地快照。
struct CarWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> CarStatusEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (CarStatusEntry) -> Void) {
        completion(makeEntry(refresh: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CarStatusEntry>) -> Void) {
        let entry = makeEntry(refresh: true)
        // 第二个条目：横幅过期后重绘一次，自动清掉执行反馈横幅
        // （WidgetKit 无法 2 秒重绘，横幅实际显示时长≈下一条目的到达时间）
        let bannerClearDate = Calendar.current.date(byAdding: .second, value: 40, to: Date()) ?? Date()
        var clearEntry = entry
        clearEntry.date = bannerClearDate
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry, clearEntry], policy: .after(nextUpdate)))
    }

    private func makeEntry(refresh: Bool) -> CarStatusEntry {
        let settings = SharedStore.loadSettings()
        var snapshot = SharedStore.loadStatusSnapshot()
        let credentials = SharedStore.loadCredentials()

        if refresh, let credentials {
            let semaphore = DispatchSemaphore(value: 0)
            let box = StatusBox()
            Task.detached {
                box.snapshot = await Self.fetchSnapshot(credentials: credentials)
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 12)
            if let fresh = box.snapshot {
                snapshot = fresh
                SharedStore.saveStatusSnapshot(fresh)
            }
        }

        // 凭据读不到时保留快照继续展示：既能显示车况，
        // 也便于定位数据通道断在哪一环（按钮点击时会提示去 App 登录）

        // 按钮配置兜底链：设置通道 → 快照内携带的配置（重签环境下设置通道可能失效）→ 默认
        var commands = settings.widgetCommands
        if commands.count != 5 {
            commands = snapshot?.widgetCommands ?? []
        }
        if commands.count != 5 {
            commands = Array(CarModelStyle.defaultWidgetCommands.prefix(5))
            while commands.count < 5 {
                commands.append(CarCommand.remoteSearchCar.rawValue)
            }
        }
        return CarStatusEntry(
            date: Date(),
            snapshot: snapshot,
            widgetCommands: commands,
            carStyle: settings.carModelStyle,
            isLoggedIn: credentials != nil || snapshot != nil
        )
    }

    /// 进程内拉车况并生成快照（与主 App 保存格式一致）
    static func fetchSnapshot(credentials: Credentials) async -> StatusSnapshot? {
        guard let (status, car, updated) = try? await CarService.refresh(credentials: credentials) else {
            return nil
        }
        SharedStore.saveCredentials(updated)
        return StatusSnapshot(carName: car.displayName, status: status)
    }
}

/// 跨并发域传递的快照盒子
private final class StatusBox: @unchecked Sendable {
    var snapshot: StatusSnapshot?
}
