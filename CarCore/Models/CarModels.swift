import Foundation
import SwiftUI

/// 控车指令。指令码与车联网开放平台一致（网页版同款）。
public enum CarCommand: String, CaseIterable, Sendable {
    case flashLight = "FlashLight"           // 闪灯
    case unlockDoor = "UnLockDoor"           // 开锁
    case lockDoor = "LockDoor"               // 闭锁
    case whistle = "Whistle"                 // 鸣笛
    case remoteSearchCar = "RemoteSearchCar" // 寻车
    case openEngine = "OpenEngine"           // 点火
    case closeEngine = "CloseEngine"         // 熄火
    case openWindow = "OpenWindow"           // 开窗
    case closeWindow = "CloseWindow"         // 关窗
    case windowSlit = "WindowSlit"           // 留缝
    case closeDormer = "CloseDormer"         // 关天窗
    case skyWindowLiftUp = "SkyWindowLiftUp" // 天窗上升
    case openAir = "openair"                 // 空调开
    case closeAir = "closeair"               // 空调关

    public var displayName: String {
        switch self {
        case .flashLight: return "闪灯"
        case .unlockDoor: return "开锁"
        case .lockDoor: return "闭锁"
        case .whistle: return "鸣笛"
        case .remoteSearchCar: return "寻车"
        case .openEngine: return "点火"
        case .closeEngine: return "熄火"
        case .openWindow: return "开窗"
        case .closeWindow: return "关窗"
        case .windowSlit: return "留缝"
        case .closeDormer: return "关天窗"
        case .skyWindowLiftUp: return "天窗上升"
        case .openAir: return "空调开"
        case .closeAir: return "空调关"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .flashLight: return "light.beacon.max"
        case .unlockDoor: return "lock.open"
        case .lockDoor: return "lock"
        case .whistle: return "speaker.wave.2"
        case .remoteSearchCar: return "car.circle"
        case .openEngine: return "flame"
        case .closeEngine: return "stop.circle"
        case .openWindow: return "wind"
        case .closeWindow: return "arrow.down.to.line"   // 网页版同款（wind.slash 在 SF Symbols 中不存在，会渲染空白）
        case .windowSlit: return "wind"
        case .closeDormer: return "sun.max"
        case .skyWindowLiftUp: return "sun.max"
        case .openAir: return "snowflake"
        case .closeAir: return "snowflake.slash"
        }
    }

    /// 高危操作（语音/快捷执行前应提醒）
    public var isDangerous: Bool {
        switch self {
        case .unlockDoor, .lockDoor, .openEngine, .closeEngine: return true
        default: return false
        }
    }

    /// 主控区四个大按钮
    public static let primaryCommands: [CarCommand] = [.flashLight, .unlockDoor, .lockDoor, .whistle]

    /// 「更多控车」中的指令
    public static let extraCommands: [CarCommand] = [
        .remoteSearchCar, .openEngine, .closeEngine,
        .openWindow, .closeWindow, .closeDormer,
        .skyWindowLiftUp, .windowSlit, .openAir, .closeAir
    ]
}

/// 车辆信息
public struct CarInfo: Sendable, Equatable {
    public let carId: String
    public let displayName: String

    public init(carId: String, displayName: String) {
        self.carId = carId
        self.displayName = displayName
    }

    /// 从 /user/cars 返回的数组中解析（字段名容错）
    public static func parse(from array: [Any]) -> [CarInfo] {
        array.compactMap { item -> CarInfo? in
            guard let dict = item as? [String: Any] else { return nil }
            let id = dict.string("carId") ?? dict.string("carID") ?? dict.string("id")
            let name = dict.string("carName") ?? dict.string("seriesName")
                ?? dict.string("modelName") ?? dict.string("name") ?? APIConfig.defaultCarName
            guard let carId = id, !carId.isEmpty else { return nil }
            return CarInfo(carId: carId, displayName: name)
        }
    }
}

/// 指令执行结果
public struct CommandResult: Sendable {
    public let ok: Bool
    public let message: String
    /// 指令任务 ID（360 全景拍照等异步任务用，普通控车为 nil）
    public let taskId: String?

    public init(ok: Bool, message: String, taskId: String? = nil) {
        self.ok = ok
        self.message = message
        self.taskId = taskId
    }
}

/// 单个轮胎气压
public struct TirePressure: Sendable, Equatable {
    public let label: String
    public let valueKPa: Double?

    public init(label: String, valueKPa: Double?) {
        self.label = label
        self.valueKPa = valueKPa
    }

    /// 低于 220kPa 视为偏低（与常用告警线一致）
    public var isLow: Bool { guard let v = valueKPa else { return false }; return v > 0 && v < 220 }
}

/// 车况汇总标志（与网页版判定逻辑一致）
public struct CarStateFlags: Sendable, Equatable {
    public var doorUnlocked = false
    public var windowOpen = false
    public var sunroofOpen = false
    public var engineRunning = false

    public init() {}

    public var flags: [(text: String, key: String)] {
        var result: [(text: String, key: String)] = []
        if doorUnlocked { result.append(("车辆已开锁", "door")) }
        if windowOpen { result.append(("车窗未关", "win")) }
        if sunroofOpen { result.append(("天窗未关", "win")) }
        if engineRunning { result.append(("发动机已启动", "engine")) }
        return result
    }

    /// 车下单一状态徽章：无异常 = 绿色「车辆正常」，否则显示首个异常（随实时刷新跟随变化）
    public var statusBadge: (text: String, key: String) {
        if let first = flags.first { return first }
        return ("车辆正常", "ok")
    }

    public var summaryText: String {
        let list = flags
        if list.isEmpty { return "一切正常" }
        if list.count == 1 { return list[0].text }
        if list.count == 2 { return list[0].text + " · " + list[1].text }
        return list[0].text + " · " + list[1].text + " 等\(list.count)项"
    }

    /// ok / door / win / engine —— 用于颜色
    public var level: String {
        flags.first?.key ?? "ok"
    }
}
