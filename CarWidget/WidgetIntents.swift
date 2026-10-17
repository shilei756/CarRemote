import AppIntents
import CarCore
import WidgetKit

/// 小组件 5 个可自定义按钮的执行逻辑：
/// 按槽位读取 App 里配置的指令（设置 → 小组件按钮），
/// 用当前登录用户的凭据在小组件进程内直接执行（不跳转 App）。
enum WidgetSlotRunner {

    static func command(forSlot slot: Int) -> CarCommand? {
        let settings = SharedStore.loadSettings()
        var commands = settings.widgetCommands
        if commands.count != 5 {
            commands = CarModelStyle.defaultWidgetCommands
        }
        guard slot >= 1, slot <= commands.count,
              let command = CarCommand(rawValue: commands[slot - 1]) else { return nil }
        return command
    }

    @MainActor
    static func perform(slot: Int) async -> String {
        let text: String
        let ok: Bool
        if let credentials = SharedStore.loadCredentials(),
           let command = command(forSlot: slot) {
            do {
                let result = try await CarService.execute(command: command, credentials: credentials)
                ok = result.ok
                text = result.ok ? "\(command.displayName)指令已发送" : "\(command.displayName)失败：\(result.message)"
            } catch {
                ok = false
                text = "\(command.displayName)失败：\(error.localizedDescription)"
            }
        } else if SharedStore.loadCredentials() == nil {
            text = "请先在「长安控车」App 中登录"
            ok = false
        } else {
            text = "请在 App「设置 → 小组件按钮」中配置该按钮"
            ok = false
        }
        // 结果落盘并刷新时间线：小组件界面显示绿✓/红✗横幅作为点击反馈
        Self.saveFeedback(text: text, ok: ok)
        WidgetCenter.shared.reloadAllTimelines()
        return text
    }

    // MARK: 执行结果反馈（小组件进程本地存储，时间线渲染时读取）

    struct LastAction: Codable {
        let text: String
        let ok: Bool
        let at: Date
    }

    private static let feedbackKey = "widget.lastAction"

    static func saveFeedback(text: String, ok: Bool) {
        if let data = try? JSONEncoder().encode(LastAction(text: text, ok: ok, at: Date())) {
            UserDefaults.standard.set(data, forKey: feedbackKey)
        }
    }

    /// 90 秒内的执行结果（用于小组件横幅反馈）
    static func lastAction() -> LastAction? {
        guard let data = UserDefaults.standard.data(forKey: feedbackKey),
              let action = try? JSONDecoder().decode(LastAction.self, from: data),
              Date().timeIntervalSince(action.at) < 90 else { return nil }
        return action
    }
}

/// 高危指令（点火/熄火等）在小组件里直接执行的确认提示：
/// 小组件进程无法弹确认框，因此高危指令执行时通过 App 打开确认（openAppWhenRun）。
private func isDangerous(_ command: CarCommand?) -> Bool {
    switch command {
    case .openEngine, .closeEngine, .openWindow:
        return true
    default:
        return false
    }
}

// MARK: - 五个槽位 Intent（按钮绑定的具体类型）

public struct WidgetSlot1Intent: AppIntent {
    public static var title: LocalizedStringResource = "小组件按钮 1"
    public static var description: IntentDescription = "执行小组件第 1 个按钮配置的指令"
    public static var openAppWhenRun: Bool = false
    public init() {}
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await WidgetSlotRunner.perform(slot: 1)))
    }
}

public struct WidgetSlot2Intent: AppIntent {
    public static var title: LocalizedStringResource = "小组件按钮 2"
    public static var description: IntentDescription = "执行小组件第 2 个按钮配置的指令"
    public static var openAppWhenRun: Bool = false
    public init() {}
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await WidgetSlotRunner.perform(slot: 2)))
    }
}

public struct WidgetSlot3Intent: AppIntent {
    public static var title: LocalizedStringResource = "小组件按钮 3"
    public static var description: IntentDescription = "执行小组件第 3 个按钮配置的指令"
    public static var openAppWhenRun: Bool = false
    public init() {}
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await WidgetSlotRunner.perform(slot: 3)))
    }
}

public struct WidgetSlot4Intent: AppIntent {
    public static var title: LocalizedStringResource = "小组件按钮 4"
    public static var description: IntentDescription = "执行小组件第 4 个按钮配置的指令"
    public static var openAppWhenRun: Bool = false
    public init() {}
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await WidgetSlotRunner.perform(slot: 4)))
    }
}

public struct WidgetSlot5Intent: AppIntent {
    public static var title: LocalizedStringResource = "小组件按钮 5"
    public static var description: IntentDescription = "执行小组件第 5 个按钮配置的指令"
    public static var openAppWhenRun: Bool = false
    public init() {}
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await WidgetSlotRunner.perform(slot: 5)))
    }
}
