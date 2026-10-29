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
        await perform(command: command(forSlot: slot))
    }

    /// 执行单条指令（锁屏快捷按钮与槽位按钮共用）。
    /// 结果落盘并刷新时间线：小组件界面显示绿✓/红✗横幅作为点击反馈
    @MainActor
    static func perform(command: CarCommand?) async -> String {
        let text: String
        let ok: Bool
        if let credentials = SharedStore.loadCredentials(), let command {
            do {
                let result = try await CarService.execute(command: command, credentials: credentials)
                ok = result.ok
                text = result.ok ? "\(command.displayName)成功" : "\(command.displayName)失败：\(CarIntentRunner.cleanReason(result.message))"
            } catch {
                ok = false
                text = "\(command.displayName)失败：\(CarIntentRunner.cleanReason(error.localizedDescription))"
            }
            // 执行成功后本地同步翻转状态：锁屏按钮图标立即反映最新锁态/发动机态
            if ok { syncSnapshotState(command: command) }
        } else if SharedStore.loadCredentials() == nil {
            text = "请先在「长安控车」App 中登录"
            ok = false
        } else {
            text = "请在 App「设置 → 小组件按钮」中配置该按钮"
            ok = false
        }
        Self.saveFeedback(text: text, ok: ok)
        WidgetCenter.shared.reloadAllTimelines()
        return text
    }

    /// 指令执行成功后更新本地快照的车况状态位（下次时间线渲染即生效）
    private static func syncSnapshotState(command: CarCommand) {
        guard var snapshot = SharedStore.loadStatusSnapshot() else { return }
        switch command {
        case .unlockDoor: snapshot.doorUnlocked = true
        case .lockDoor: snapshot.doorUnlocked = false
        case .openEngine: snapshot.engineRunning = true
        case .closeEngine: snapshot.engineRunning = false
        default: return
        }
        snapshot.updatedAt = Date()
        SharedStore.saveStatusSnapshot(snapshot)
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

    /// 35 秒内的执行结果（用于小组件横幅反馈；WidgetKit 最小重绘粒度为分钟级，无法 2 秒消失）
    static func lastAction() -> LastAction? {
        guard let data = UserDefaults.standard.data(forKey: feedbackKey),
              let action = try? JSONDecoder().decode(LastAction.self, from: data),
              Date().timeIntervalSince(action.at) < 35 else { return nil }
        return action
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

// MARK: - 锁屏快捷控车 Intent（iOS 17 交互式小组件，不解锁手机直接执行）

/// 开关车门锁（智能反向）：已锁止 → 开锁；已开锁 → 闭锁
public struct LockToggleIntent: AppIntent {
    public static var title: LocalizedStringResource = "开关车门锁"
    public static var description: IntentDescription = "车门已锁则开锁，已开锁则闭锁（不解锁手机直接控车）"
    public static var openAppWhenRun: Bool = false
    public init() {}
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let command: CarCommand = SharedStore.loadStatusSnapshot()?.doorUnlocked == true ? .lockDoor : .unlockDoor
        return .result(dialog: IntentDialog(stringLiteral: await WidgetSlotRunner.perform(command: command)))
    }
}

/// 点火/熄火（智能反向）：发动机未运行 → 点火；运行中 → 熄火
public struct EngineToggleIntent: AppIntent {
    public static var title: LocalizedStringResource = "点火 / 熄火"
    public static var description: IntentDescription = "发动机未运行则远程点火，运行中则熄火（不解锁手机直接控车）"
    public static var openAppWhenRun: Bool = false
    public init() {}
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let command: CarCommand = SharedStore.loadStatusSnapshot()?.engineRunning == true ? .closeEngine : .openEngine
        return .result(dialog: IntentDialog(stringLiteral: await WidgetSlotRunner.perform(command: command)))
    }
}

/// 寻车：鸣笛 + 闪灯（车钥匙找车同款效果）
public struct WhistleFindIntent: AppIntent {
    public static var title: LocalizedStringResource = "寻车"
    public static var description: IntentDescription = "鸣笛闪灯帮助快速找到爱车（不解锁手机直接执行）"
    public static var openAppWhenRun: Bool = false
    public init() {}
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: IntentDialog(stringLiteral: await WidgetSlotRunner.perform(command: .remoteSearchCar)))
    }
}
