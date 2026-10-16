import Foundation

/// 车况数据。
///
/// 车联网接口 `car/data?keys=*` 返回的字段在不同车型间存在差异
/// （网页版同样做了多字段名兼容），因此这里采用「原始字典 + 候选键名」解析，
/// 单个字段缺失不会影响其他字段展示。
///
/// `raw` 为不可变字典，跨并发域传递是安全的，故标注 `@unchecked Sendable`。
public struct CarStatus: @unchecked Sendable {
    public let raw: [String: Any]

    public init(raw: [String: Any]) {
        self.raw = raw
    }

    public init?(jsonObject: Any) {
        guard let dict = jsonObject as? [String: Any] else { return nil }
        self.raw = dict
    }

    // MARK: - 通用取值（容错：数字/字符串/布尔均可）

    private static func number(_ dict: [String: Any], _ keys: [String]) -> Double? {
        for key in keys {
            guard let value = dict[key] else { continue }
            if let d = value as? Double { return d }
            if let i = value as? Int { return Double(i) }
            if let s = value as? String, let d = Double(s) { return d }
            if let b = value as? Bool { return b ? 1 : 0 }
        }
        return nil
    }

    private static func isOne(_ dict: [String: Any], _ keys: [String]) -> Bool {
        for key in keys {
            guard let value = dict[key] else { continue }
            if let i = value as? Int { return i == 1 }
            if let s = value as? String { return s == "1" || s.lowercased() == "true" }
            if let b = value as? Bool { return b }
        }
        return false
    }

    // MARK: - 油量 / 续航 / 里程

    /// 剩余续航 km
    public var remainingRangeKm: Double? {
        Self.number(raw, ["remainedOilMile", "remainOilMile", "enduranceMileage", "remainMileage"])
    }

    /// 剩余油量 L
    public var fuelLeftLiters: Double? {
        Self.number(raw, ["fuelLeftover", "remainOil", "fuelLeft", "oilLeft"])
    }

    /// 总里程 km
    public var totalOdometerKm: Double? {
        Self.number(raw, ["totalOdometer", "totalMileage", "totalOdo"])
    }

    /// 上次行程里程 km
    public var lastTripKm: Double? {
        Self.number(raw, ["igniteCumulativeMileage", "lastTripMileage"])
    }

    /// 上次行程油耗 L
    public var lastTripOilLiters: Double? {
        Self.number(raw, ["igniteCumulativeOil"])
    }

    /// 电瓶电压 V
    public var batteryVoltage: Double? {
        Self.number(raw, ["batteryVoltage", "voltage", "batteryVoltageValue"])
    }

    /// 车外温度 °C
    public var vehicleTempC: Double? {
        Self.number(raw, ["vehicleTemperature", "outsideTemp", "ambientTemperature"])
    }

    /// 空调设定温度 °C
    public var acTempC: Double? {
        Self.number(raw, ["airConditioningSetTemperature", "acTemp"])
    }

    // MARK: - 胎压 kPa（左前 / 右前 / 左后 / 右后）

    public var tirePressures: [TirePressure] {
        [
            TirePressure(label: "左前", valueKPa: Self.number(raw, ["lfTyrePressure", "leftFrontTyrePressure"])),
            TirePressure(label: "右前", valueKPa: Self.number(raw, ["rfTyrePressure", "rightFrontTyrePressure"])),
            TirePressure(label: "左后", valueKPa: Self.number(raw, ["lrTyrePressure", "leftRearTyrePressure"])),
            TirePressure(label: "右后", valueKPa: Self.number(raw, ["rrTyrePressure", "rightRearTyrePressure"]))
        ]
    }

    // MARK: - 门窗 / 发动机状态

    /// 任一车门/后备箱/前机盖处于已解锁状态
    public var doorUnlocked: Bool {
        Self.isOne(raw, ["leftFrontDoorStatus", "rightFrontDoorStatus", "leftRearDoorStatus",
                         "rightRearDoorStatus", "trunk", "hood"])
    }

    /// 任一车窗未关
    public var windowOpen: Bool {
        Self.isOne(raw, ["diverWindow", "driverWindow", "leftFrontDoorrWindow",
                         "leftFrontDoorWindow", "passengerWindow", "leftRearWindow",
                         "rightRearWindow", "window"])
    }

    /// 天窗未关
    public var sunroofOpen: Bool {
        Self.isOne(raw, ["sunroof", "skyWindow", "dormer"])
    }

    /// 发动机是否运行（判定逻辑与网页版一致）
    public var engineRunning: Bool {
        let speed = Self.number(raw, ["vehicleSpeed", "speed"]) ?? 0
        if speed > 0 { return true }
        if let fire = Self.number(raw, ["fireStatus"]), fire == 2 { return false }
        if let rpm = Self.number(raw, ["revolutionSpeed", "engineSpeed", "rpm", "engineRevolution"]) {
            if rpm >= 16383 { return false }        // 0x3FFF / 0xFFFF 为无效哨兵值
            if rpm > 0 { return true }
        }
        return (Self.number(raw, ["engineStatus"]) ?? 0) == 1
    }

    /// 车辆位置（部分车型上报）
    public var location: (latitude: Double, longitude: Double)? {
        guard let lat = Self.number(raw, ["latitude", "lat", "LAT", "gpsLatitude"]),
              let lon = Self.number(raw, ["longitude", "lon", "lng", "LON", "gpsLongitude"]),
              abs(lat) > 0.001, abs(lon) > 0.001 else { return nil }
        return (lat, lon)
    }

    // MARK: - 汇总

    public var stateFlags: CarStateFlags {
        var flags = CarStateFlags()
        flags.doorUnlocked = doorUnlocked
        flags.windowOpen = windowOpen
        flags.sunroofOpen = sunroofOpen
        flags.engineRunning = engineRunning
        return flags
    }

    /// 格式化数值：整数则不保留小数点
    public static func format(_ value: Double?, unit: String = "") -> String {
        guard let value else { return "--" }
        let rounded = (value * 10).rounded() / 10
        let text: String
        if rounded == rounded.rounded() {
            text = String(format: "%.0f", rounded)
        } else {
            text = String(format: "%.1f", rounded)
        }
        return unit.isEmpty ? text : text + unit
    }
}
