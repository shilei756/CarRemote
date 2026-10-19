import AppIntents
import WidgetKit
import Foundation

// MARK: - 统一控车 Intent（Siri 重新设计）

/// 控车指令选项（Siri / 快捷指令的参数枚举，对应 CarCommand）
@available(iOS 16.0, *)
public enum CarCommandOption: String, AppEnum, CaseIterable, Sendable {
    case unlockDoor
    case lockDoor
    case flashLight
    case whistle
    case remoteSearchCar
    case openWindow
    case closeWindow
    case windowSlit
    case closeDormer
    case skyWindowLiftUp
    case openEngine
    case closeEngine
    case openAir
    case closeAir

    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "控车指令")
    }

    public static var caseDisplayRepresentations: [CarCommandOption: DisplayRepresentation] {
        [
            .unlockDoor: DisplayRepresentation(title: "开锁", image: DisplayRepresentation.Image(systemName: "lock.open")),
            .lockDoor: DisplayRepresentation(title: "闭锁", image: DisplayRepresentation.Image(systemName: "lock")),
            .flashLight: DisplayRepresentation(title: "闪灯", image: DisplayRepresentation.Image(systemName: "light.beacon.max")),
            .whistle: DisplayRepresentation(title: "鸣笛", image: DisplayRepresentation.Image(systemName: "speaker.wave.2")),
            .remoteSearchCar: DisplayRepresentation(title: "寻车", image: DisplayRepresentation.Image(systemName: "car.circle")),
            .openWindow: DisplayRepresentation(title: "降窗", image: DisplayRepresentation.Image(systemName: "wind")),
            .closeWindow: DisplayRepresentation(title: "升窗", image: DisplayRepresentation.Image(systemName: "arrow.down.to.line")),
            .windowSlit: DisplayRepresentation(title: "留缝", image: DisplayRepresentation.Image(systemName: "wind")),
            .closeDormer: DisplayRepresentation(title: "关天窗", image: DisplayRepresentation.Image(systemName: "sun.max")),
            .skyWindowLiftUp: DisplayRepresentation(title: "天窗上翘", image: DisplayRepresentation.Image(systemName: "sun.max")),
            .openEngine: DisplayRepresentation(title: "远程点火", image: DisplayRepresentation.Image(systemName: "flame")),
            .closeEngine: DisplayRepresentation(title: "远程熄火", image: DisplayRepresentation.Image(systemName: "stop.circle")),
            .openAir: DisplayRepresentation(title: "开空调", image: DisplayRepresentation.Image(systemName: "snowflake")),
            .closeAir: DisplayRepresentation(title: "关空调", image: DisplayRepresentation.Image(systemName: "snowflake.slash"))
        ]
    }

    /// 对应的业务指令
    public var command: CarCommand {
        switch self {
        case .unlockDoor: return .unlockDoor
        case .lockDoor: return .lockDoor
        case .flashLight: return .flashLight
        case .whistle: return .whistle
        case .remoteSearchCar: return .remoteSearchCar
        case .openWindow: return .openWindow
        case .closeWindow: return .closeWindow
        case .windowSlit: return .windowSlit
        case .closeDormer: return .closeDormer
        case .skyWindowLiftUp: return .skyWindowLiftUp
        case .openEngine: return .openEngine
        case .closeEngine: return .closeEngine
        case .openAir: return .openAir
        case .closeAir: return .closeAir
        }
    }
}

/// 统一控车指令：Siri 说「控制车辆」→ 追问要控制什么 → 高危操作语音确认后执行。
/// 相比逐条 Intent，一条指令覆盖全部控车能力，快捷指令 App 中也可选择具体指令。
@available(iOS 16.0, *)
public struct ControlCarIntent: AppIntent {
    public static var title: LocalizedStringResource = "控制车辆"
    public static var description: IntentDescription = "向你的爱车发送任意控车指令（开锁、闭锁、空调、车窗、点火等）"
    public static var openAppWhenRun: Bool = false

    @Parameter(title: "指令", requestValueDialog: "想对车做什么？")
    public var command: CarCommandOption

    public init() {}

    public init(command: CarCommandOption) {
        self.command = command
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let cmd = command.command
        // 高危操作（开锁/闭锁/点火/熄火）先语音确认，取消则直接结束
        if cmd.isDangerous {
            try await confirmDangerous(IntentDialog("确认要执行「\(cmd.displayName)」吗？"))
        }
        let message = await CarIntentRunner.run(command: cmd)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
