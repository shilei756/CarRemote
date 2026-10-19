import AppIntents
import WidgetKit
import Foundation

/// 控车 Intent 的公共执行逻辑：
/// 读取本地凭据 → 检查设置中的语音开关 → 执行指令 → 刷新小组件。
/// 执行结果统一为 Outcome.speech（Siri 朗读 / 快捷指令展示 / 小组件横幅三处同源）。
public enum CarIntentRunner {

    /// 指令执行结果：ok = 车机平台是否接受；speech = 成功/失败明确播报文本
    public struct Outcome {
        public let ok: Bool
        public let speech: String

        public init(ok: Bool, speech: String) {
            self.ok = ok
            self.speech = speech
        }
    }

    public static func run(command: CarCommand) async -> Outcome {
        let settings = SharedStore.loadSettings()
        guard settings.siriAllows(command: command) else {
            return Outcome(ok: false, speech: "「\(command.displayName)」尚未在 App 的「设置 → 语音命令」中开放")
        }
        guard let credentials = SharedStore.loadCredentials() else {
            return Outcome(ok: false, speech: "请先在「长安控车」App 中登录")
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
                return Outcome(ok: true, speech: "\(command.displayName)成功")
            }
            return Outcome(ok: false, speech: "\(command.displayName)失败：\(cleanReason(result.message))")
        } catch {
            return Outcome(ok: false, speech: "\(command.displayName)失败：\(cleanReason(error.localizedDescription))")
        }
    }

    /// 失败原因清洗：取首行去空白，空则给默认文案（避免播报裸 error 或空串）
    public static func cleanReason(_ raw: String) -> String {
        let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "请检查网络后重试" : trimmed
    }
}

// MARK: - 开锁

@available(iOS 16.0, *)
public struct UnlockCarIntent: AppIntent {
    public static var title: LocalizedStringResource = "解锁车辆"
    public static var description: IntentDescription = "向你的爱车发送解锁指令"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .unlockDoor)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 闭锁

@available(iOS 16.0, *)
public struct LockCarIntent: AppIntent {
    public static var title: LocalizedStringResource = "锁定车辆"
    public static var description: IntentDescription = "向你的爱车发送闭锁指令"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .lockDoor)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 闪灯

@available(iOS 16.0, *)
public struct FlashLightsIntent: AppIntent {
    public static var title: LocalizedStringResource = "闪灯"
    public static var description: IntentDescription = "让车辆闪灯，便于寻车"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .flashLight)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 鸣笛

@available(iOS 16.0, *)
public struct HonkHornIntent: AppIntent {
    public static var title: LocalizedStringResource = "鸣笛"
    public static var description: IntentDescription = "让车辆鸣笛，便于寻车"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .whistle)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 寻车

@available(iOS 16.0, *)
public struct FindCarIntent: AppIntent {
    public static var title: LocalizedStringResource = "寻车"
    public static var description: IntentDescription = "让车辆闪灯鸣笛，帮你找到停车位置"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .remoteSearchCar)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 点火（高危）

@available(iOS 16.0, *)
public struct StartEngineIntent: AppIntent {
    public static var title: LocalizedStringResource = "远程点火"
    public static var description: IntentDescription = "远程启动发动机（高危操作）"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // 高危操作：Siri 语音确认后执行（iOS 18+ 用新版 API，16/17 用废弃但可用的旧 API）
        try await confirmDangerous(IntentDialog("确认要远程启动发动机吗？"))
        let outcome = await CarIntentRunner.run(command: .openEngine)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 熄火（高危）

@available(iOS 16.0, *)
public struct StopEngineIntent: AppIntent {
    public static var title: LocalizedStringResource = "远程熄火"
    public static var description: IntentDescription = "远程关闭发动机（高危操作）"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // 高危操作：Siri 语音确认后执行（iOS 18+ 用新版 API，16/17 用废弃但可用的旧 API）
        try await confirmDangerous(IntentDialog("确认要远程关闭发动机吗？"))
        let outcome = await CarIntentRunner.run(command: .closeEngine)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 关窗

@available(iOS 16.0, *)
public struct CloseWindowsIntent: AppIntent {
    public static var title: LocalizedStringResource = "关闭车窗"
    public static var description: IntentDescription = "关闭所有车窗"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .closeWindow)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 空调开 / 关

@available(iOS 16.0, *)
public struct OpenACIntent: AppIntent {
    public static var title: LocalizedStringResource = "打开空调"
    public static var description: IntentDescription = "远程开启空调"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .openAir)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

@available(iOS 16.0, *)
public struct CloseACIntent: AppIntent {
    public static var title: LocalizedStringResource = "关闭空调"
    public static var description: IntentDescription = "远程关闭空调"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .closeAir)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}
