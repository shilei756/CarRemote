import WidgetKit
import SwiftUI
import CarCore

// MARK: - 时间线条目与提供器

struct CakocheWidgetEntry: TimelineEntry {
    var date: Date
    let snapshot: StatusSnapshot?
    let isLoggedIn: Bool

    static var placeholder: CakocheWidgetEntry {
        CakocheWidgetEntry(date: Date(), snapshot: nil, isLoggedIn: true)
    }
}

/// 时间线提供器：先用共享通道（App Group）里的快照立即渲染，
/// 随后后台拉一次真实车况，内容有变化才 reload（与正式版 CarWidget 同套路）。
/// 主 App 每次刷新车况也会主动 reloadAllTimelines，双保险。
struct CakocheWidgetProvider: TimelineProvider {

    func placeholder(in context: Context) -> CakocheWidgetEntry { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (CakocheWidgetEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CakocheWidgetEntry>) -> Void) {
        completion(buildTimeline())
    }

    private func makeEntry() -> CakocheWidgetEntry {
        let snapshot = SharedStore.loadStatusSnapshot() ?? CakocheWidgetLocalStore.loadSnapshot()
        let credentials = CakocheWidgetRunner.credentials
        return CakocheWidgetEntry(date: Date(),
                                  snapshot: snapshot,
                                  isLoggedIn: credentials != nil || snapshot != nil)
    }

    private func buildTimeline() -> Timeline<CakocheWidgetEntry> {
        let entry = makeEntry()
        var entries: [CakocheWidgetEntry] = [entry]
        // 第二条目：横幅过期后重绘一次，自动清掉执行反馈
        var clearEntry = makeEntry()
        clearEntry.date = Date().addingTimeInterval(40)
        entries.append(clearEntry)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date()
        let timeline = Timeline(entries: entries, policy: .after(nextUpdate))

        // 立即渲染后异步刷新车况；内容有变化才 reload，避免刷新死循环
        guard let credentials = CakocheWidgetRunner.credentials else { return timeline }
        let previous = entry.snapshot
        Task.detached {
            guard let (status, car, updated) = try? await CarService.refresh(credentials: credentials) else { return }
            CakocheWidgetRunner.saveCredentials(updated)
            let fresh = StatusSnapshot(carName: car.displayName, status: status)
            CakocheWidgetLocalStore.saveSnapshot(fresh)
            if !Self.sameContent(fresh, previous) {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        return timeline
    }

    /// 忽略 updatedAt 的内容级比较
    static func sameContent(_ a: StatusSnapshot?, _ b: StatusSnapshot?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return a.carName == b.carName
            && a.remainingRangeKm == b.remainingRangeKm
            && a.fuelLeftLiters == b.fuelLeftLiters
            && a.totalOdometerKm == b.totalOdometerKm
            && a.batteryVoltage == b.batteryVoltage
            && a.vehicleTempC == b.vehicleTempC
            && a.doorUnlocked == b.doorUnlocked
            && a.windowOpen == b.windowOpen
            && a.engineRunning == b.engineRunning
            && a.tirePressures == b.tirePressures
    }
}

// MARK: - 小组件本地存储（免签/巨魔无 App Group 环境的兜底通道）

/// 与正式版 WidgetLocalStore 同思路：键名独立（cakoche.widget.local.*），
/// 小组件进程自己的沙盒 UserDefaults，不依赖任何共享权限。
enum CakocheWidgetLocalStore {
    private static let credentialsKey = "cakoche.widget.local.credentials"
    private static let snapshotKey = "cakoche.widget.local.snapshot"
    private static let defaults = UserDefaults.standard

    static func loadCredentials() -> Credentials? {
        guard let data = defaults.data(forKey: credentialsKey) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }
    static func saveCredentials(_ credentials: Credentials?) {
        if let credentials, let data = try? JSONEncoder().encode(credentials) {
            defaults.set(data, forKey: credentialsKey)
        } else {
            defaults.removeObject(forKey: credentialsKey)
        }
    }
    static func loadSnapshot() -> StatusSnapshot? {
        guard let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(StatusSnapshot.self, from: data)
    }
    static func saveSnapshot(_ snapshot: StatusSnapshot?) {
        if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: snapshotKey)
        } else {
            defaults.removeObject(forKey: snapshotKey)
        }
    }
}

// MARK: - 指令执行（小组件进程内直接下发）

enum CakocheWidgetRunner {

    /// 凭据双通道：共享通道（App Group / Keychain）→ 小组件本地沙盒
    static var credentials: Credentials? {
        SharedStore.loadCredentials() ?? CakocheWidgetLocalStore.loadCredentials()
    }

    static func saveCredentials(_ credentials: Credentials) {
        SharedStore.saveCredentials(credentials)
        CakocheWidgetLocalStore.saveCredentials(credentials)
    }

    // MARK: 防误触（1.2.0：所有指令都需 8 秒内点两次才真正下发）

    private static let pendingKey = "cakoche.widget.pendingCommand"
    private static let pendingAtKey = "cakoche.widget.pendingAt"
    private static let window: TimeInterval = 8

    /// 返回提示文案 = 本次点按被拦截（第一次点按），nil = 放行（第二次点按）
    static func registerTap(command: CarCommand) -> String? {
        let defaults = UserDefaults.standard
        let pending = defaults.string(forKey: pendingKey)
        let at = defaults.double(forKey: pendingAtKey)
        let fresh = Date().timeIntervalSince1970 - at < window
        if fresh, pending == command.rawValue {
            defaults.removeObject(forKey: pendingKey)
            defaults.removeObject(forKey: pendingAtKey)
            return nil
        }
        defaults.set(command.rawValue, forKey: pendingKey)
        defaults.set(Date().timeIntervalSince1970, forKey: pendingAtKey)
        return "请再点一次确认"
    }

    static func pendingCommand() -> CarCommand? {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: pendingKey),
              Date().timeIntervalSince1970 - defaults.double(forKey: pendingAtKey) < window,
              let command = CarCommand(rawValue: raw) else { return nil }
        return command
    }

    // MARK: 执行结果反馈（35 秒内的横幅）

    struct LastAction: Codable {
        let text: String
        let ok: Bool
        let at: Date
    }

    private static let feedbackKey = "cakoche.widget.lastAction"

    static func saveFeedback(text: String, ok: Bool) {
        if let data = try? JSONEncoder().encode(LastAction(text: text, ok: ok, at: Date())) {
            UserDefaults.standard.set(data, forKey: feedbackKey)
        }
    }

    static func lastAction() -> LastAction? {
        guard let data = UserDefaults.standard.data(forKey: feedbackKey),
              let action = try? JSONDecoder().decode(LastAction.self, from: data),
              Date().timeIntervalSince(action.at) < 35 else { return nil }
        return action
    }

    // MARK: 5 槽自定义按钮配置（App「我的 → 小组件按钮」里配置）

    /// 槽位指令兜底链：设置通道 → 快照携带 → 默认
    static func resolvedCommands() -> [CarCommand?] {
        var raws = SharedStore.loadSettings().widgetCommands
        if raws.count != 5 {
            raws = SharedStore.loadStatusSnapshot()?.widgetCommands ?? []
        }
        if raws.count != 5 {
            raws = Array(CarModelStyle.defaultWidgetCommands.prefix(5))
            while raws.count < 5 { raws.append(CarCommand.remoteSearchCar.rawValue) }
        }
        return raws.prefix(5).map { CarCommand(rawValue: $0) }
    }

    @MainActor
    static func perform(slot: Int) async -> String {
        let commands = resolvedCommands()
        let command = slot >= 1 && slot <= commands.count ? commands[slot - 1] ?? CarCommand.remoteSearchCar : nil
        return await perform(command: command)
    }

    // MARK: 执行入口

    @MainActor
    static func perform(command: CarCommand?) async -> String {
        guard let command else { return "指令无效" }
        if let hint = registerTap(command: command) {
            WidgetCenter.shared.reloadAllTimelines()
            return hint
        }
        let text: String
        let ok: Bool
        if let credentials = credentials {
            do {
                let result = try await CarService.execute(command: command, credentials: credentials)
                ok = result.ok
                text = result.ok ? "\(command.displayName)成功" : "\(command.displayName)失败：\(CarIntentRunner.cleanReason(result.message))"
            } catch {
                ok = false
                text = "\(command.displayName)失败：\(CarIntentRunner.cleanReason(error.localizedDescription))"
            }
            if ok { syncSnapshotState(command: command) }
        } else {
            text = "请先在 CAKOCHE App 登录"
            ok = false
        }
        saveFeedback(text: text, ok: ok)
        WidgetCenter.shared.reloadAllTimelines()
        return text
    }

    /// 执行成功后本地翻转状态位，下次渲染立即反映最新锁态/发动机态
    private static func syncSnapshotState(command: CarCommand) {
        guard var snapshot = SharedStore.loadStatusSnapshot() ?? CakocheWidgetLocalStore.loadSnapshot() else { return }
        switch command {
        case .unlockDoor: snapshot.doorUnlocked = true
        case .lockDoor, .oneKeyLock: snapshot.doorUnlocked = false
        case .openEngine: snapshot.engineRunning = true
        case .closeEngine: snapshot.engineRunning = false
        default: return
        }
        snapshot.updatedAt = Date()
        SharedStore.saveStatusSnapshot(snapshot)
        CakocheWidgetLocalStore.saveSnapshot(snapshot)
    }
}
