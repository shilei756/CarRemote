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

    /// 从本地车况快照重建（「秒开」用：冷启动先用上次车况把控车页渲染出来，
    /// 无需等待网络）。门窗/发动机等派生状态按快照布尔值回填为分区字段，
    /// 与真实车「聚合字段兜底」行为一致；标量字段原样回填，保证展示数值与刷新后一致。
    public init(snapshot: StatusSnapshot) {
        var raw: [String: Any] = [:]
        raw["remainedOilMile"] = snapshot.remainingRangeKm
        raw["fuelLeftover"] = snapshot.fuelLeftLiters
        raw["totalOdometer"] = snapshot.totalOdometerKm
        raw["batteryVoltage"] = snapshot.batteryVoltage
        raw["vehicleTemperature"] = snapshot.vehicleTempC
        raw["airConditioningSetTemperature"] = snapshot.acTempC
        // 门窗状态：整组同态回填为分区字段
        let doorVal: Int = snapshot.doorUnlocked ? 1 : 0
        raw["leftFrontDoorStatus"] = doorVal
        raw["rightFrontDoorStatus"] = doorVal
        raw["leftRearDoorStatus"] = doorVal
        raw["rightRearDoorStatus"] = doorVal
        raw["trunk"] = doorVal
        raw["hood"] = doorVal
        let winVal: Int = snapshot.windowOpen ? 1 : 0
        raw["diverWindow"] = winVal
        raw["passengerWindow"] = winVal
        raw["leftRearWindow"] = winVal
        raw["rightRearWindow"] = winVal
        raw["sunroof"] = snapshot.sunroofOpen ? 1 : 0
        // 发动机：用 engineStatus 表达「是否运转」，无转速/车速则按此判定
        raw["engineStatus"] = snapshot.engineRunning ? 1 : 0
        // 胎压（缺失项为 nil，展示「--」）
        let tires = snapshot.tirePressures
        if tires.count >= 4 {
            raw["lfTyrePressure"] = tires[0]
            raw["rfTyrePressure"] = tires[1]
            raw["lrTyrePressure"] = tires[2]
            raw["rrTyrePressure"] = tires[3]
        }
        self.raw = raw
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

    /// 候选键中是否存在任意一个（用于判断「是否上报过分区字段」）
    private static func hasAny(_ dict: [String: Any], _ keys: [String]) -> Bool {
        keys.contains { dict[$0] != nil }
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

    // MARK: - 逐门 / 逐窗细分状态（3D 车模联动用）

    /// 逐扇车门与逐扇车窗的独立状态。
    ///
    /// 车联网接口 `car/data?keys=*` 上报的是**分区字段**：
    ///   车门：`leftFrontDoorStatus` / `rightFrontDoorStatus` / `leftRearDoorStatus`
    ///         / `rightRearDoorStatus` / `trunk` / `hood`
    ///   车窗：`diverWindow`（主驾·左前）/ `passengerWindow`（副驾·右前）
    ///         / `leftRearWindow` / `rightRearWindow`
    ///
    /// 取值语义（与智慧云控网页版 `carState()` 一致）：
    ///   - `*DoorStatus == 1` → **该门已解锁**（注意：解锁 ≠ 打开，车门关闭时也可能为 1）
    ///   - `*Window == 1`    → **该窗未关**
    ///   - `window == 1`     → 全车车窗未关（部分车型只上报这一个聚合字段）
    ///
    /// 某分区字段缺失时，对应门/窗按「未解锁 / 已关闭」处理；
    /// 若整组门字段全缺，则用聚合 `doorUnlocked` 兜底（全部门按已解锁处理）。
    public struct DoorsAndWindows: Sendable, Equatable {
        /// 左前门已解锁
        public var leftFrontDoorUnlocked = false
        /// 右前门已解锁
        public var rightFrontDoorUnlocked = false
        /// 左后门已解锁
        public var leftRearDoorUnlocked = false
        /// 右后门已解锁
        public var rightRearDoorUnlocked = false
        /// 后备箱已解锁
        public var trunkUnlocked = false
        /// 前机盖已解锁
        public var hoodUnlocked = false
        /// 左前窗未关
        public var leftFrontWindowOpen = false
        /// 右前窗未关
        public var rightFrontWindowOpen = false
        /// 左后窗未关
        public var leftRearWindowOpen = false
        /// 右后窗未关
        public var rightRearWindowOpen = false
        /// 天窗未关
        public var sunroofOpen = false
        /// 是否上报过任何分区车门字段（false = 只有聚合字段）
        public var hasPerDoorFields = false
        /// 是否上报过任何分区车窗字段（false = 只有聚合字段）
        public var hasPerWindowFields = false

        public init() {}

        /// 是否有任意一扇门处于未锁状态
        public var anyDoorUnlocked: Bool {
            leftFrontDoorUnlocked || rightFrontDoorUnlocked
                || leftRearDoorUnlocked || rightRearDoorUnlocked
                || trunkUnlocked || hoodUnlocked
        }

        /// 是否有任意一扇窗未关
        public var anyWindowOpen: Bool {
            leftFrontWindowOpen || rightFrontWindowOpen
                || leftRearWindowOpen || rightRearWindowOpen
        }
    }

    /// 逐门逐窗状态（3D 车模与真实车况联动）
    public var doorsAndWindows: DoorsAndWindows {
        var s = DoorsAndWindows()
        s.sunroofOpen = sunroofOpen

        // ---- 车门 ----
        let fl = Self.isOne(raw, ["leftFrontDoorStatus"])
        let fr = Self.isOne(raw, ["rightFrontDoorStatus"])
        let rl = Self.isOne(raw, ["leftRearDoorStatus"])
        let rr = Self.isOne(raw, ["rightRearDoorStatus"])
        let tk = Self.isOne(raw, ["trunk"])
        let hd = Self.isOne(raw, ["hood"])
        let perDoorSeen = Self.hasAny(raw, ["leftFrontDoorStatus", "rightFrontDoorStatus",
                                            "leftRearDoorStatus", "rightRearDoorStatus"])
        if perDoorSeen {
            s.leftFrontDoorUnlocked = fl
            s.rightFrontDoorUnlocked = fr
            s.leftRearDoorUnlocked = rl
            s.rightRearDoorUnlocked = rr
            s.trunkUnlocked = tk
            s.hoodUnlocked = hd
        } else {
            // 只有聚合字段：整组门按同一状态处理
            let any = doorUnlocked
            s.leftFrontDoorUnlocked = any
            s.rightFrontDoorUnlocked = any
            s.leftRearDoorUnlocked = any
            s.rightRearDoorUnlocked = any
            s.trunkUnlocked = any
            s.hoodUnlocked = any
        }
        s.hasPerDoorFields = perDoorSeen

        // ---- 车窗 ----
        let winFL = Self.isOne(raw, ["diverWindow", "driverWindow",
                                     "leftFrontDoorrWindow", "leftFrontDoorWindow"])
        let winFR = Self.isOne(raw, ["passengerWindow"])
        let winRL = Self.isOne(raw, ["leftRearWindow"])
        let winRR = Self.isOne(raw, ["rightRearWindow"])
        let perWindowSeen = Self.hasAny(raw, ["diverWindow", "driverWindow",
                                              "leftFrontDoorrWindow", "leftFrontDoorWindow",
                                              "passengerWindow", "leftRearWindow", "rightRearWindow"])
        if perWindowSeen {
            s.leftFrontWindowOpen = winFL
            s.rightFrontWindowOpen = winFR
            s.leftRearWindowOpen = winRL
            s.rightRearWindowOpen = winRR
        } else {
            // 只有聚合 window 字段：全部车窗一起处理
            let any = windowOpen
            s.leftFrontWindowOpen = any
            s.rightFrontWindowOpen = any
            s.leftRearWindowOpen = any
            s.rightRearWindowOpen = any
        }
        s.hasPerWindowFields = perWindowSeen
        return s
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

    /// 车辆是否已启动（点火/发动机运转）
    /// 3D 车模据此点亮大灯：车辆启动后亮灯，熄火即灭灯。
    /// 判定要求「有明确的运转证据」：行驶中 / 有效转速 / 发动机运行标志；
    /// 只有点火信号但没有任何运转证据时，视为静止（不亮灯），
    /// 避免出现「车况正常但大灯常亮」的违和感（1.1.4 实机反馈）。
    public var isVehicleStarted: Bool {
        // 行驶中：最直接的启动证据
        if (Self.number(raw, ["vehicleSpeed", "speed"]) ?? 0) > 0 { return true }
        // 发动机运行标志
        if let engine = Self.number(raw, ["engineStatus"]), engine == 1 { return true }
        // 有效转速（非哨兵值且 > 0）
        if let rpm = Self.number(raw, ["revolutionSpeed", "engineSpeed", "rpm", "engineRevolution"]) {
            if rpm < 16383 && rpm > 0 { return true }   // 0x3FFF / 0xFFFF 为无效哨兵值
            // 转速为 0：发动机未运转 → 未启动
            return false
        }
        // 接口只上报点火状态时，以点火状态为准
        if let fire = Self.number(raw, ["fireStatus"]) { return fire == 1 }
        return false
    }

    /// 车辆是否在行驶中（车速 > 0 km/h）
    /// 3D 车模据此转动车轮：行驶中车轮滚动，静止不动。
    public var isVehicleDriving: Bool {
        (Self.number(raw, ["vehicleSpeed", "speed"]) ?? 0) > 0
    }

    /// 车轮是否应当滚动。
    /// 规则（对齐用户诉求「静止时车轮不许转」）：
    ///   - 接口上报了车速：车速 > 0 才转；
    ///   - 接口完全不上报车速字段：退化为「车辆已启动即视为动态」，避免车轮永远死转/永不动。
    public var shouldRollWheels: Bool {
        if let speed = Self.number(raw, ["vehicleSpeed", "speed"]) {
            return speed > 0
        }
        return isVehicleStarted
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
