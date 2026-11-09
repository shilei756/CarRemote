import Foundation
import CarCore

/// 1.10.0 小组件防误触「A 方案」：二次点按确认。
///
/// 规则（只对高危指令生效，且必须在「我的 → 小组件防误触」打开开关后才启用）：
///  - 第一次点按：不执行任何指令，只记下「待确认指令 + 时间」，提示「再点一次确认」；
///  - 8 秒内第二次点按【同一个】按钮：清掉待确认，真正下发指令；
///  - 超过 8 秒、或中途点了别的按钮：旧的待确认自动作废，重新进入第一次点按。
///
/// 关键设计：**拦截发生在 AppIntent 的执行入口，而不是靠 WidgetKit 重绘**。
/// 桌面小组件的时间线刷新粒度是分钟级且会被系统节流，如果把确认状态做成
/// SwiftUI 的 @State，用户连点两次时第二次很可能拿到的是旧快照，指令就丢了。
/// 这里把待确认写进小组件进程自己的 UserDefaults（主屏 + 锁屏共享同一份），
/// 每次点按都实时读写，因此即使界面完全没重绘，两条链路也都能 100% 执行。
///
/// 开关的跨进程可达性：主 App 写入 `SharedStore.saveWidgetGuardEnabled` 的多通道
/// （App Group / 共享容器文件 / Keychain）；免签 / 巨魔环境下共享通道可能全断，
/// 所以时间线刷新时会把读到的值缓存进小组件沙盒，此后按缓存值兜底。
enum WidgetGuard {

    /// 二次点按的有效窗口（秒）
    static let window: TimeInterval = 8

    private static let defaults = UserDefaults.standard
    private static let pendingKey = "widget.guard.pending"
    private static let cachedEnabledKey = "widget.guard.enabled"

    private struct Pending: Codable {
        let command: String
        let at: Date
    }

    /// 开关是否打开。默认关闭 —— 没主动开过开关的用户，小组件仍是一键直接执行。
    static var isEnabled: Bool {
        if let shared = SharedStore.loadWidgetGuardEnabledRaw() { return shared }
        if defaults.object(forKey: cachedEnabledKey) != nil {
            return defaults.bool(forKey: cachedEnabledKey)
        }
        return SharedStore.loadSettings().widgetGuardEnabled
    }

    /// 时间线刷新时把共享开关值缓存到小组件沙盒：
    /// 免签 / 巨魔环境共享通道时通时断，缓存保证开关不会突然失效。
    static func syncFromShared() {
        if let shared = SharedStore.loadWidgetGuardEnabledRaw() {
            defaults.set(shared, forKey: cachedEnabledKey)
        }
    }

    /// 8 秒内仍有效的待确认指令；超时解析为 nil（自动放弃，不下发任何指令）。
    static func pendingCommand() -> CarCommand? {
        guard let data = defaults.data(forKey: pendingKey),
              let pending = try? JSONDecoder().decode(Pending.self, from: data),
              Date().timeIntervalSince(pending.at) < window,
              let command = CarCommand(rawValue: pending.command) else {
            return nil
        }
        return command
    }

    /// 橙色横幅文案。视图直接读 UserDefaults，不依赖 entry 字段或即时重绘。
    static func pendingText() -> String? {
        guard let command = pendingCommand() else { return nil }
        return "再点一次确认「\(command.displayName)」"
    }

    /// 点按登记。
    /// - 返回非 nil：本次**不要执行**，返回值是给用户的提示文案（第一次点按）。
    /// - 返回 nil：无需确认，或已完成二次确认，调用方继续正常下发指令。
    @discardableResult
    static func registerTap(command: CarCommand?) -> String? {
        guard isEnabled, let command, command.isDangerous else {
            // 开关关闭 / 非高危指令：顺手清掉残留待确认（点其它按钮即取消）
            clearPending()
            return nil
        }
        let previous = pendingCommand()
        clearPending()
        if previous == command {
            return nil   // 8 秒内第二次点按同一指令 → 执行
        }
        let pending = Pending(command: command.rawValue, at: Date())
        if let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: pendingKey)
        }
        return "再点一次确认「\(command.displayName)」"
    }

    static func clearPending() {
        defaults.removeObject(forKey: pendingKey)
    }
}
