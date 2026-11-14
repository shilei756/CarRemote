import AppIntents
import WidgetKit
import Foundation
import CarCore

// =============================================================
// 查看类 Intent · 每一项都能单独拖进快捷指令，并返回可继续用的文本
//
// 与 App 首页「刷新车况」同一条链路（token → /user/cars → /car/data），
// 查询完顺手刷新本地快照与小组件，Siri 说完、回桌面数字就是新的。
// 360 全景不在本清单内（需取图 + 轮询，不适合做成静默动作）。
// =============================================================

/// 查看类 Intent 的公共数据层
enum CarQuery {

    static func load() async throws -> (status: CarStatus, car: CarInfo) {
        guard let credentials = SharedStore.loadCredentials() else {
            throw APIError.server("请先在 App 内登录（手机号 + 控车码）")
        }
        let (status, car, updated) = try await CarService.refresh(credentials: credentials)
        SharedStore.saveCredentials(updated)
        SharedStore.saveStatusSnapshot(StatusSnapshot(carName: car.displayName, status: status))
        WidgetCenter.shared.reloadAllTimelines()
        return (status, car)
    }

    /// 统一失败文案：查询失败 + 首行原因
    static func failure(_ error: Error) -> String {
        "查询失败：\(CarIntentRunner.cleanReason(error.localizedDescription))"
    }

    static func fmt(_ value: Double?) -> String {
        CarStatus.format(value)
    }
}

// MARK: - 续航与油量

/// 只回答「还能跑多远、还剩多少油」，适合放进表盘 / 桌面 / 车载支架自动化。
@available(iOS 16.0, *)
struct RangeFuelIntent: AppIntent {
    static var title: LocalizedStringResource = "续航与油量"
    static var description: IntentDescription = "读取剩余续航、剩余油量、总里程与电瓶电压"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        do {
            let (status, car) = try await CarQuery.load()
            let text = [
                "\(car.displayName) 续航 \(CarQuery.fmt(status.remainingRangeKm)) 公里",
                "油量 \(CarQuery.fmt(status.fuelLeftLiters)) 升",
                "总里程 \(CarQuery.fmt(status.totalOdometerKm)) 公里",
                "电瓶 \(CarQuery.fmt(status.batteryVoltage)) 伏"
            ].joined(separator: "，")
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        } catch {
            let text = CarQuery.failure(error)
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        }
    }
}

// MARK: - 四轮胎压

@available(iOS 16.0, *)
struct TirePressureIntent: AppIntent {
    static var title: LocalizedStringResource = "四轮胎压"
    static var description: IntentDescription = "读取四个轮胎的胎压，并指出偏低的那一条"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        do {
            let (status, _) = try await CarQuery.load()
            let tires = status.tirePressures
            let values = tires.map { "\($0.label) \(CarQuery.fmt($0.valueKPa))" }.joined(separator: "、")
            let low = tires.filter { $0.isLow }.map { $0.label }
            let tail = low.isEmpty ? "，四轮正常" : "，\(low.joined(separator: "、"))偏低"
            let text = "胎压（kPa）：\(values)\(tail)"
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        } catch {
            let text = CarQuery.failure(error)
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        }
    }
}

// MARK: - 门窗锁闭状态

@available(iOS 16.0, *)
struct DoorsWindowsIntent: AppIntent {
    static var title: LocalizedStringResource = "门窗锁闭状态"
    static var description: IntentDescription = "只查四门、后备箱、前机盖、四窗与天窗有没有关好"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        do {
            let (status, _) = try await CarQuery.load()
            let dw = status.doorsAndWindows

            let doors: [(String, Bool)] = [
                ("左前门", dw.leftFrontDoorUnlocked), ("右前门", dw.rightFrontDoorUnlocked),
                ("左后门", dw.leftRearDoorUnlocked), ("右后门", dw.rightRearDoorUnlocked),
                ("后备箱", dw.trunkUnlocked), ("前机盖", dw.hoodUnlocked)
            ]
            let windows: [(String, Bool)] = [
                ("左前窗", dw.leftFrontWindowOpen), ("右前窗", dw.rightFrontWindowOpen),
                ("左后窗", dw.leftRearWindowOpen), ("右后窗", dw.rightRearWindowOpen),
                ("天窗", dw.sunroofOpen)
            ]
            let unlockedDoors = doors.filter { $0.1 }.map { $0.0 }
            let openWindows = windows.filter { $0.1 }.map { $0.0 }

            let doorLine = unlockedDoors.isEmpty
                ? "四门、后备箱、前机盖均已锁好"
                : "未锁：\(unlockedDoors.joined(separator: "、"))"
            let windowLine = openWindows.isEmpty
                ? "四窗与天窗均已关闭"
                : "未关：\(openWindows.joined(separator: "、"))"
            let text = "\(doorLine)；\(windowLine)"
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        } catch {
            let text = CarQuery.failure(error)
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        }
    }
}

// MARK: - 车内温度与空调

@available(iOS 16.0, *)
struct CabinClimateIntent: AppIntent {
    static var title: LocalizedStringResource = "车内温度与空调"
    static var description: IntentDescription = "读取车内实际温度、空调设定温度与发动机状态"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        do {
            let (status, _) = try await CarQuery.load()
            let engine = status.engineRunning ? "发动机运行中" : "发动机已熄火"
            let text = "车内 \(CarQuery.fmt(status.vehicleTempC))℃，空调设定 \(CarQuery.fmt(status.acTempC))℃，\(engine)"
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        } catch {
            let text = CarQuery.failure(error)
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        }
    }
}

// MARK: - 账号与空调授权

/// 「我的 → 账号授权」的语音版本：手机号（脱敏）+ 新版空调授权剩余天数。
@available(iOS 16.0, *)
struct AccountAuthIntent: AppIntent {
    static var title: LocalizedStringResource = "账号与空调授权"
    static var description: IntentDescription = "查看当前登录手机号与新版空调授权的剩余天数"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let credentials = SharedStore.loadCredentials() else {
            let text = "请先在 App 内登录（手机号 + 控车码）"
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        }
        let phone = credentials.phone
        let masked = phone.count == 11
            ? String(phone.prefix(3)) + "****" + String(phone.suffix(4))
            : phone
        let text = "账号 \(masked)，新版空调 \(ACService.websiteAuthorizationText())"
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}
