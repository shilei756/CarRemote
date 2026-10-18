import AppIntents
import WidgetKit
import Foundation

/// 控车 Intent 的公共执行逻辑：
/// 读取本地凭据 → 检查设置中的语音开关 → 执行指令 → 刷新小组件。
public enum CarIntentRunner {

    public static func run(command: CarCommand) async -> String {
        let settings = SharedStore.loadSettings()
        guard settings.siriAllows(command: command) else {
            return "「\(command.displayName)」尚未在 App 的「设置 → 语音命令」中开放"
        }
        guard let credentials = SharedStore.loadCredentials() else {
            return "请先在「长安控车」App 中登录"
        }
        do {
            // 空调与 App 内保持一致：新版模式走开放平台链路（Siri 无调温弹窗，按车机默认设定）
            let result: CommandResult
            if (command == .openAir || command == .closeAir), SharedStore.loadACMode() == .new {
                result = try await ACService.executeOfficial(command: command, credentials: credentials)
            } else {
                result = try await CarService.execute(command: command, credentials: credentials)
            }
            WidgetCenter.shared.reloadAllTimelines()
            if result.ok {
                return "\(command.displayName)指令已发送"
            }
            return "\(command.displayName)失败：\(result.message)"
        } catch {
            return "\(command.displayName)失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - 开锁

public struct UnlockCarIntent: AppIntent {
    public static var title: LocalizedStringResource = "解锁车辆"
    public static var description: IntentDescription = "向你的爱车发送解锁指令"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await CarIntentRunner.run(command: .unlockDoor)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - 闭锁

public struct LockCarIntent: AppIntent {
    public static var title: LocalizedStringResource = "锁定车辆"
    public static var description: IntentDescription = "向你的爱车发送闭锁指令"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await CarIntentRunner.run(command: .lockDoor)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - 闪灯

public struct FlashLightsIntent: AppIntent {
    public static var title: LocalizedStringResource = "闪灯"
    public static var description: IntentDescription = "让车辆闪灯，便于寻车"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await CarIntentRunner.run(command: .flashLight)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - 鸣笛

public struct HonkHornIntent: AppIntent {
    public static var title: LocalizedStringResource = "鸣笛"
    public static var description: IntentDescription = "让车辆鸣笛，便于寻车"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await CarIntentRunner.run(command: .whistle)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - 寻车

public struct FindCarIntent: AppIntent {
    public static var title: LocalizedStringResource = "寻车"
    public static var description: IntentDescription = "让车辆闪灯鸣笛，帮你找到停车位置"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await CarIntentRunner.run(command: .remoteSearchCar)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - 点火（高危）

public struct StartEngineIntent: AppIntent {
    public static var title: LocalizedStringResource = "远程点火"
    public static var description: IntentDescription = "远程启动发动机（高危操作）"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // 高危操作：Siri 语音确认后执行
        try await requestConfirmation(
            conditions: [],
            actionName: .continue,
            dialog: IntentDialog("确认要远程启动发动机吗？")
        )
        let message = await CarIntentRunner.run(command: .openEngine)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - 熄火（高危）

public struct StopEngineIntent: AppIntent {
    public static var title: LocalizedStringResource = "远程熄火"
    public static var description: IntentDescription = "远程关闭发动机（高危操作）"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // 高危操作：Siri 语音确认后执行
        try await requestConfirmation(
            conditions: [],
            actionName: .continue,
            dialog: IntentDialog("确认要远程关闭发动机吗？")
        )
        let message = await CarIntentRunner.run(command: .closeEngine)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - 关窗

public struct CloseWindowsIntent: AppIntent {
    public static var title: LocalizedStringResource = "关闭车窗"
    public static var description: IntentDescription = "关闭所有车窗"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await CarIntentRunner.run(command: .closeWindow)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

// MARK: - 空调开 / 关

public struct OpenACIntent: AppIntent {
    public static var title: LocalizedStringResource = "打开空调"
    public static var description: IntentDescription = "远程开启空调"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await CarIntentRunner.run(command: .openAir)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

public struct CloseACIntent: AppIntent {
    public static var title: LocalizedStringResource = "关闭空调"
    public static var description: IntentDescription = "远程关闭空调"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await CarIntentRunner.run(command: .closeAir)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
