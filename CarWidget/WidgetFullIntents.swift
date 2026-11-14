import AppIntents
import WidgetKit
import Foundation
import CarCore

// =============================================================
// 小组件「全功能」指令集（1.11.0）
//
// 把 16 条控车指令逐条独立封装成 App Intent，外加空调定温、刷新车况
// 与 6 个查看动作。全部复用 WidgetSlotRunner.perform —— 因此自动继承：
//   · 空调按用户「新版 / 官方版」选择分流（本次核心修复）
//   · 防误触二次确认（App 内开关）
//   · 共享通道 / 小组件独立登录 双通道凭据
//   · 绿✓红✗ 反馈横幅 + 时间线刷新
//
// 为什么放在小组件扩展目标：App Intents 元数据只对 App / App Extension
// 目标自动抽取，放在 CarCore 框架里要 iOS 17 的 AppIntentsPackage 才可见。
// 标题统一加「小组件 ·」前缀，与 App 内那 25 个动作区分，快捷指令里不会重名。
//
// 360 全景（拍照 + 轮询取图）不在清单内，与 App 侧保持一致。
// =============================================================

/// 统一执行入口：把结果文本包成 IntentDialog
@MainActor
private func widgetDialog(_ command: CarCommand, temperature: Int? = nil) async -> IntentDialog {
    let text = await WidgetSlotRunner.perform(command: command, temperature: temperature)
    return IntentDialog(stringLiteral: text)
}

// MARK: - 16 条控车指令（逐条独立封装）

struct WidgetUnlockIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 开锁"
    static var description: IntentDescription = "打开车门锁"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.unlockDoor))
    }
}

struct WidgetLockIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 闭锁"
    static var description: IntentDescription = "锁上车门"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.lockDoor))
    }
}

struct WidgetOneKeyLockIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 一键闭锁"
    static var description: IntentDescription = "锁车门并在 4.5 秒后关闭全部车窗"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.oneKeyLock))
    }
}

struct WidgetFlashIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 闪灯"
    static var description: IntentDescription = "闪灯提醒"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.flashLight))
    }
}

struct WidgetHonkIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 鸣笛"
    static var description: IntentDescription = "鸣笛提醒"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.whistle))
    }
}

struct WidgetFindCarIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 寻车"
    static var description: IntentDescription = "鸣笛闪灯，快速找到爱车"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.remoteSearchCar))
    }
}

struct WidgetStartEngineIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 远程点火"
    static var description: IntentDescription = "远程启动发动机"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.openEngine))
    }
}

struct WidgetStopEngineIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 远程熄火"
    static var description: IntentDescription = "远程关闭发动机"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.closeEngine))
    }
}

struct WidgetOpenWindowIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 降窗"
    static var description: IntentDescription = "降下车窗"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.openWindow))
    }
}

struct WidgetCloseWindowIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 关窗"
    static var description: IntentDescription = "关闭车窗"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.closeWindow))
    }
}

struct WidgetWindowSlitIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 车窗留缝"
    static var description: IntentDescription = "车窗留一条缝通风"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.windowSlit))
    }
}

struct WidgetCloseSunroofIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 关天窗"
    static var description: IntentDescription = "关闭天窗"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.closeDormer))
    }
}

struct WidgetTiltSunroofIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 天窗上翘"
    static var description: IntentDescription = "天窗上翘通风"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.skyWindowLiftUp))
    }
}

struct WidgetOpenACIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 开空调"
    static var description: IntentDescription = "远程开启空调，按你设置的「新版 / 官方版」链路下发"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.openAir))
    }
}

struct WidgetCloseACIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 关空调"
    static var description: IntentDescription = "远程关闭空调，按你设置的「新版 / 官方版」链路下发"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: await widgetDialog(.closeAir))
    }
}

// MARK: - 空调定温（新版链路支持指定 16~32℃）

struct WidgetSetACTemperatureIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 开空调并设定温度"
    static var description: IntentDescription = "开启空调并指定目标温度；官方版链路按车机设定执行"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "温度（摄氏度）")
    var temperature: Int

    init() {}
    init(temperature: Int) { self.temperature = temperature }

    static var parameterSummary: some ParameterSummary {
        Summary("打开空调，设定 \(\.$temperature) 摄氏度")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let target = min(32, max(16, temperature))
        let text = await WidgetSlotRunner.perform(command: .openAir, temperature: target)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

// MARK: - 查看类动作（返回文本，可继续串「朗读 / 发微信 / 写备忘录」）

/// 查看类公共数据层：只读快照（离线即时），或联网刷新一次车况。
enum WidgetCarQuery {

    static func snapshot() -> StatusSnapshot? {
        SharedStore.loadStatusSnapshot() ?? WidgetLocalStore.loadSnapshot()
    }

    /// 联网刷新：与 App 首页「刷新车况」同一条链路，双通道落盘 + 刷新时间线
    static func refreshText() async -> String {
        guard let credentials = SharedStore.loadCredentials() ?? WidgetLocalStore.loadCredentials() else {
            return "请先在「长安控车」App 登录，或用「快捷指令」运行「小组件独立登录」绑定"
        }
        do {
            let (status, car, updated) = try await CarService.refresh(credentials: credentials)
            SharedStore.saveCredentials(updated)
            WidgetLocalStore.saveCredentials(updated)
            let snapshot = StatusSnapshot(carName: car.displayName, status: status)
            SharedStore.saveStatusSnapshot(snapshot)
            WidgetLocalStore.saveSnapshot(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
            return describe(snapshot)
        } catch {
            return "刷新车况失败：\(CarIntentRunner.cleanReason(error.localizedDescription))"
        }
    }

    static func fmt(_ value: Double?) -> String { CarStatus.format(value) }

    /// 全字段总览（与 App 内「车辆状态」播报同源的精简版）
    static func describe(_ s: StatusSnapshot) -> String {
        var lines: [String] = ["\(s.carName)"]
        lines.append("续航 \(fmt(s.remainingRangeKm)) 公里，油量 \(fmt(s.fuelLeftLiters)) 升，总里程 \(fmt(s.totalOdometerKm)) 公里，电瓶 \(fmt(s.batteryVoltage)) 伏")
        lines.append("门锁\(s.doorUnlocked ? "未锁" : "已锁")，车窗\(s.windowOpen ? "未关" : "已关")，天窗\(s.sunroofOpen ? "未关" : "已关")，发动机\(s.engineRunning ? "运行中" : "已熄火")")
        if let t = s.vehicleTempC { lines.append("车内温度 \(fmt(t)) ℃") }
        if let t = s.acTempC { lines.append("空调设定 \(fmt(t)) ℃") }
        let pressures = s.tirePressures.enumerated().compactMap { pair -> String? in
            guard let value = pair.element else { return nil }
            let names = ["左前", "右前", "左后", "右后"]
            let index = pair.offset
            let name = index < names.count ? names[index] : "轮胎\(index + 1)"
            return "\(name) \(fmt(value))"
        }
        if !pressures.isEmpty { lines.append("胎压 \(pressures.joined(separator: "、")) kPa") }
        lines.append("空调链路：\(WidgetSlotRunner.usesNewAC ? "新版（开放平台）" : "官方版（直连）")")
        return lines.joined(separator: "；")
    }

    static func noData() -> String {
        "暂无车况数据，请先打开 App 下拉刷新，或运行「小组件 · 刷新车况」"
    }

    static func cached(_ build: (StatusSnapshot) -> String) -> String {
        guard let s = snapshot() else { return noData() }
        return build(s)
    }
}

struct WidgetRefreshStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 刷新车况"
    static var description: IntentDescription = "联网拉取最新车况并同步到桌面小组件，返回车况文本"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = await WidgetCarQuery.refreshText()
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct WidgetVehicleStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 车辆状态"
    static var description: IntentDescription = "查看门锁、车窗、天窗、发动机、续航、油量、胎压与空调链路"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = WidgetCarQuery.cached { WidgetCarQuery.describe($0) }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct WidgetRangeFuelIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 续航与油量"
    static var description: IntentDescription = "查看剩余续航、剩余油量、总里程与电瓶电压"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = WidgetCarQuery.cached { s in
            "\(s.carName) 续航 \(WidgetCarQuery.fmt(s.remainingRangeKm)) 公里，油量 \(WidgetCarQuery.fmt(s.fuelLeftLiters)) 升，总里程 \(WidgetCarQuery.fmt(s.totalOdometerKm)) 公里，电瓶 \(WidgetCarQuery.fmt(s.batteryVoltage)) 伏"
        }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct WidgetTirePressureIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 四轮胎压"
    static var description: IntentDescription = "查看四轮胎压，并标出低于 220 kPa 的轮胎"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = WidgetCarQuery.cached { s in
            let names = ["左前", "右前", "左后", "右后"]
            let parts = s.tirePressures.enumerated().map { pair -> String in
                let index = pair.offset
                let name = index < names.count ? names[index] : "轮胎\(index + 1)"
                guard let value = pair.element else { return "\(name) 无数据" }
                let low = value > 0 && value < 220 ? "（偏低）" : ""
                return "\(name) \(WidgetCarQuery.fmt(value)) kPa\(low)"
            }
            return parts.isEmpty ? "暂无胎压数据" : parts.joined(separator: "，")
        }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct WidgetDoorsWindowsIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 门窗锁闭状态"
    static var description: IntentDescription = "查看车门、车窗、天窗有没有关好，发动机是否熄火"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = WidgetCarQuery.cached { s in
            "门锁\(s.doorUnlocked ? "未锁" : "已锁")，车窗\(s.windowOpen ? "未关" : "已关")，天窗\(s.sunroofOpen ? "未关" : "已关")，发动机\(s.engineRunning ? "运行中" : "已熄火")"
        }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct WidgetCabinClimateIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 车内温度与空调"
    static var description: IntentDescription = "查看车内温度、空调设定温度与当前空调控制链路"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = WidgetCarQuery.cached { s in
            "车内温度 \(WidgetCarQuery.fmt(s.vehicleTempC)) ℃，空调设定 \(WidgetCarQuery.fmt(s.acTempC)) ℃，当前链路：\(WidgetSlotRunner.usesNewAC ? "新版（开放平台）" : "官方版（直连）")"
        }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct WidgetACModeIntent: AppIntent {
    static var title: LocalizedStringResource = "小组件 · 空调模式"
    static var description: IntentDescription = "查看小组件当前会按哪种空调链路下发指令（跟随 App 设置）"
    static var openAppWhenRun: Bool = false
    init() {}
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let text = WidgetSlotRunner.usesNewAC
            ? "当前为新版空调（长安开放平台），开 / 关空调走网站授权链路，支持指定温度。可在 App「设置 → 新版空调」切换。"
            : "当前为官方版空调（直连），开 / 关空调按车机当前设定执行。可在 App「设置 → 新版空调」切换。"
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}
