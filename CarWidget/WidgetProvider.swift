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
                       carStyle: .yidong, isLoggedIn: true)
    }
}

/// 时间线提供器：
/// - 主 App 每次刷新车况都会 reloadAllTimelines，即时更新；
/// - 时间线刷新时先用本地快照**立即渲染**（不阻塞，原实现最长等 12 秒网络，
///   用户看到的是白转的加载圈），随后在后台拉一次官网车况，
///   内容有变化时再主动请求重绘（凭据来自共享存储）。
struct CarWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> CarStatusEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (CarStatusEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CarStatusEntry>) -> Void) {
        let entry = makeEntry()
        // 第二个条目：横幅过期后重绘一次，自动清掉执行反馈横幅
        // （WidgetKit 无法 2 秒重绘，横幅实际显示时长≈下一条目的到达时间）
        let bannerClearDate = Calendar.current.date(byAdding: .second, value: 40, to: Date()) ?? Date()
        var clearEntry = entry
        clearEntry.date = bannerClearDate
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        completion(Timeline(entries: [entry, clearEntry], policy: .after(nextUpdate)))

        // 立即渲染后异步刷新车况；内容有变化才 reload，
        // 避免「刷新→reload→再刷新」的死循环（updatedAt 每次都不同，必须比内容）
        guard let credentials = SharedStore.loadCredentials() else { return }
        let previous = entry.snapshot
        Task.detached {
            guard let fresh = await Self.fetchSnapshot(credentials: credentials) else { return }
            let changed = !Self.sameContent(fresh, previous)
            SharedStore.saveStatusSnapshot(fresh)
            if changed {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// 忽略 updatedAt 的内容级比较（车况数据有变化才算变化）
    static func sameContent(_ a: StatusSnapshot?, _ b: StatusSnapshot?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.carName == b.carName
            && a.remainingRangeKm == b.remainingRangeKm
            && a.fuelLeftLiters == b.fuelLeftLiters
            && a.totalOdometerKm == b.totalOdometerKm
            && a.batteryVoltage == b.batteryVoltage
            && a.doorUnlocked == b.doorUnlocked
            && a.windowOpen == b.windowOpen
            && a.sunroofOpen == b.sunroofOpen
            && a.engineRunning == b.engineRunning
            && a.tirePressures == b.tirePressures
    }

    private func makeEntry() -> CarStatusEntry {
        let settings = SharedStore.loadSettings()
        let snapshot = SharedStore.loadStatusSnapshot()
        let credentials = SharedStore.loadCredentials()

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
