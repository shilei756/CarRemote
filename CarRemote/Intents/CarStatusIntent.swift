import AppIntents
import WidgetKit
import Foundation
import CarCore

/// 车辆状态（详细版：Siri / 快捷指令 / 小组件共用）。
///
/// 用户要的「车辆状态」不是一句「续航多少」，而是：
/// 四门是否锁好、四窗与天窗是否关好、车有没有熄火、四轮胎压，
/// 外加续航 / 油量 / 总里程 / 电瓶电压。
/// 结果同时作为文本返回，快捷指令里可以接着「朗读」「发微信」「写入备忘录」。
@available(iOS 16.0, *)
struct CarStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "车辆状态"
    static var description: IntentDescription = "查询四门锁态、四窗与天窗、是否熄火、四轮胎压、续航与油量"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        do {
            let (status, car) = try await CarQuery.load()
            let text = Self.describe(status, carName: car.displayName)
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        } catch {
            let text = "查询失败：\(CarIntentRunner.cleanReason(error.localizedDescription))"
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        }
    }

    /// 逐项拼装播报文本（Siri 朗读 / 快捷指令结果 / 小组件反馈三处同源）
    static func describe(_ status: CarStatus, carName: String) -> String {
        let dw = status.doorsAndWindows
        // 局部函数包装：CarStatus.format 带默认参数，直接引用成函数值会丢失默认值
        func fmt(_ value: Double?) -> String { CarStatus.format(value) }

        // 门：逐扇 + 后备箱 + 前机盖（字段名语义见 CarStatus.doorsAndWindows）
        let doorNames: [(String, Bool)] = [
            ("左前门", dw.leftFrontDoorUnlocked), ("右前门", dw.rightFrontDoorUnlocked),
            ("左后门", dw.leftRearDoorUnlocked), ("右后门", dw.rightRearDoorUnlocked),
            ("后备箱", dw.trunkUnlocked), ("前机盖", dw.hoodUnlocked)
        ]
        let unlockedDoors = doorNames.filter { $0.1 }.map { $0.0 }
        let doorLine = unlockedDoors.isEmpty
            ? "四门与后备箱、前机盖均已锁好"
            : "未锁：\(unlockedDoors.joined(separator: "、"))"

        // 窗：四窗 + 天窗
        let windowNames: [(String, Bool)] = [
            ("左前窗", dw.leftFrontWindowOpen), ("右前窗", dw.rightFrontWindowOpen),
            ("左后窗", dw.leftRearWindowOpen), ("右后窗", dw.rightRearWindowOpen),
            ("天窗", dw.sunroofOpen)
        ]
        let openWindows = windowNames.filter { $0.1 }.map { $0.0 }
        let windowLine = openWindows.isEmpty
            ? "四窗与天窗均已关闭"
            : "未关：\(openWindows.joined(separator: "、"))"

        // 熄火 / 发动机
        let engineLine = status.engineRunning ? "发动机运行中（未熄火）" : "发动机已熄火"

        // 胎压：四轮
        let tires = status.tirePressures
        let tireLine = "胎压 左前 \(fmt(tires[0].valueKPa))、右前 \(fmt(tires[1].valueKPa))、左后 \(fmt(tires[2].valueKPa))、右后 \(fmt(tires[3].valueKPa)) kPa"

        let basicLine = "续航 \(fmt(status.remainingRangeKm)) 公里，油量 \(fmt(status.fuelLeftLiters)) 升，总里程 \(fmt(status.totalOdometerKm)) 公里，电瓶电压 \(fmt(status.batteryVoltage)) 伏"

        return [
            "\(carName) 车辆状态：",
            "锁车：\(doorLine)",
            "车窗：\(windowLine)",
            "发动机：\(engineLine)",
            tireLine,
            basicLine
        ].joined(separator: "\n")
    }
}

// MARK: - 车辆位置

/// 查询车辆位置。
/// 与 App 内「车辆位置」卡片同源：car/location 接口返回的具体地址、城市、
/// 定位时间、经纬度与车速；Siri 朗读、快捷指令结果里直接可读。
@available(iOS 16.0, *)
struct CarLocationIntent: AppIntent {
    static var title: LocalizedStringResource = "查询车辆位置"
    static var description: IntentDescription = "读取车辆最新定位：地址、定位时间、经纬度与车速"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let credentials = SharedStore.loadCredentials() else {
            let text = "请先在 App 内登录（手机号 + 控车码）"
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        }
        do {
            let (token, updatedCredentials) = try await AuthService.validAccessToken(for: credentials)
            SharedStore.saveCredentials(updatedCredentials)
            let cars = try await CarService.fetchCars(accessToken: token)
            guard let car = cars.first else {
                let text = "未获取到车辆信息，请确认账号已绑定车辆"
                return .result(value: text, dialog: IntentDialog(stringLiteral: text))
            }
            let location = try await CarService.fetchLocation(carId: car.carId, accessToken: token)
            var lines: [String] = []
            lines.append("车辆位置：\(location.address.isEmpty ? "暂无具体地址" : location.address)")
            if !location.city.isEmpty { lines.append("城市：\(location.city)") }
            if !location.gpsTime.isEmpty { lines.append("定位时间：\(location.gpsTime)") }
            lines.append(String(format: "经纬度：%.6f, %.6f", location.latitude, location.longitude))
            if let speed = location.speed { lines.append(String(format: "车速：%.0f km/h", speed)) }
            let text = lines.joined(separator: "\n")
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        } catch {
            let text = "位置查询失败：\(CarIntentRunner.cleanReason(error.localizedDescription))"
            return .result(value: text, dialog: IntentDialog(stringLiteral: text))
        }
    }
}
