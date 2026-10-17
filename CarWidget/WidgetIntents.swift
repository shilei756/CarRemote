import AppIntents
import CarCore

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
        guard let credentials = SharedStore.loadCredentials() else {
            return "请先在「长安控车」App 中登录"
        }
        guard let command = command(forSlot: slot) else {
            return "请在 App「设置 → 小组件按钮」中配置该按钮"
        }
        do {
            let result = try await CarService.execute(command: command, credentials: credentials)
            WidgetCenter.shared.reloadAllTimelines()
            return result.ok ? "\(command.displayName)指令已发送" : "\(command.displayName)失败：\(result.message)"
        } catch {
            return "\(command.displayName)失败：\(error.localizedDescription)"
        }
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
