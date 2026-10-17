import WidgetKit
import SwiftUI
import CarCore

/// 小组件时间线条目：车况快照 + 用户自定义的 5 个控车按钮 + 车型外观
struct CarStatusEntry: TimelineEntry {
    let date: Date
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
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextUpdate)))
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

        // 未登录时清掉旧快照，避免显示别人的车（数据隔离）
        if credentials == nil { snapshot = nil }

        var commands = settings.widgetCommands
        if commands.count != 5 {
            // 兼容脏数据：不足/超出 5 个时用默认值补齐
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
            isLoggedIn: credentials != nil
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
