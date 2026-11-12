import AppIntents
import SwiftUI
import CarCore
import WidgetKit

// MARK: - 交互按钮 Intent（iOS 17 小组件进程内直接执行，不解锁手机控车）

/// 开关车门锁（智能反向）：已锁止 → 开锁；已开锁 → 闭锁
struct CakocheLockToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "开关车门锁"
    static var description: IntentDescription = "车门已锁则开锁，已开锁则闭锁"
    static var openAppWhenRun: Bool = false
    public init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = SharedStore.loadStatusSnapshot() ?? CakocheWidgetLocalStore.loadSnapshot()
        let command: CarCommand = snapshot?.doorUnlocked == true ? .lockDoor : .unlockDoor
        return .result(dialog: IntentDialog(stringLiteral: await CakocheWidgetRunner.perform(command: command)))
    }
}

/// 点火 / 熄火（智能反向）
struct CakocheEngineToggleIntent: AppIntent {
    static var title: LocalizedStringResource = "点火 / 熄火"
    static var description: IntentDescription = "发动机未运行则点火，运行中则熄火"
    static var openAppWhenRun: Bool = false
    public init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot = SharedStore.loadStatusSnapshot() ?? CakocheWidgetLocalStore.loadSnapshot()
        let command: CarCommand = snapshot?.engineRunning == true ? .closeEngine : .openEngine
        return .result(dialog: IntentDialog(stringLiteral: await CakocheWidgetRunner.perform(command: command)))
    }
}

/// 寻车：鸣笛闪灯
struct CakocheWhistleIntent: AppIntent {
    static var title: LocalizedStringResource = "寻车"
    static var description: IntentDescription = "鸣笛闪灯帮助快速找到爱车"
    static var openAppWhenRun: Bool = false
    public init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: IntentDialog(stringLiteral: await CakocheWidgetRunner.perform(command: .remoteSearchCar)))
    }
}

/// 闪灯
struct CakocheFlashIntent: AppIntent {
    static var title: LocalizedStringResource = "闪灯"
    static var description: IntentDescription = "闪灯提醒"
    static var openAppWhenRun: Bool = false
    public init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: IntentDialog(stringLiteral: await CakocheWidgetRunner.perform(command: .flashLight)))
    }
}

// MARK: - 5 个自定义槽位 Intent（App「我的 → 小组件按钮」配置的指令）

struct CakocheSlot1Intent: AppIntent {
    static var title: LocalizedStringResource = "小组件按钮 1"
    static var description: IntentDescription = "执行小组件第 1 个按钮配置的指令"
    static var openAppWhenRun: Bool = false
    public init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await CakocheWidgetRunner.perform(slot: 1)))
    }
}

struct CakocheSlot2Intent: AppIntent {
    static var title: LocalizedStringResource = "小组件按钮 2"
    static var description: IntentDescription = "执行小组件第 2 个按钮配置的指令"
    static var openAppWhenRun: Bool = false
    public init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await CakocheWidgetRunner.perform(slot: 2)))
    }
}

struct CakocheSlot3Intent: AppIntent {
    static var title: LocalizedStringResource = "小组件按钮 3"
    static var description: IntentDescription = "执行小组件第 3 个按钮配置的指令"
    static var openAppWhenRun: Bool = false
    public init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await CakocheWidgetRunner.perform(slot: 3)))
    }
}

struct CakocheSlot4Intent: AppIntent {
    static var title: LocalizedStringResource = "小组件按钮 4"
    static var description: IntentDescription = "执行小组件第 4 个按钮配置的指令"
    static var openAppWhenRun: Bool = false
    public init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await CakocheWidgetRunner.perform(slot: 4)))
    }
}

struct CakocheSlot5Intent: AppIntent {
    static var title: LocalizedStringResource = "小组件按钮 5"
    static var description: IntentDescription = "执行小组件第 5 个按钮配置的指令"
    static var openAppWhenRun: Bool = false
    public init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(stringLiteral: await CakocheWidgetRunner.perform(slot: 5)))
    }
}

// MARK: - 按钮视图（iOS 17 交互式 / iOS 16 深链回 App 兜底）

/// iOS 17+ 用 AppIntent 直接执行；iOS 16 没有交互式小组件，Link 打开 App 控车。
@ViewBuilder
func cakocheWidgetButton<I: AppIntent, Label: View>(
    intent: I,
    @ViewBuilder label: () -> Label
) -> some View {
    if #available(iOSApplicationExtension 17.0, *) {
        Button(intent: intent) { label() }
            .buttonStyle(.plain)
    } else {
        Link(destination: URL(string: "cakoche://home")!) { label() }
    }
}
