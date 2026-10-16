import Foundation

/// 本地记录模型：油耗记录 / 维保记录。
///
/// 网页版的「油耗统计 / 维保提醒」页面使用浏览器 localStorage 存储
/// （无服务端接口），原生 App 对应改为 App Group UserDefaults 存储，
/// 这样记录不随账号变化丢失，也能被小组件扩展读取。
public struct FuelRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// 加油日期
    public var date: Date
    /// 加油时里程表读数 km
    public var odometerKm: Double
    /// 加油量 L
    public var liters: Double
    /// 单价 元/L（可选）
    public var pricePerLiter: Double?
    /// 总花费 元（可选）
    public var totalCost: Double?
    /// 是否加满（用于油耗估算）
    public var isFull: Bool
    /// 备注（加油站等）
    public var note: String

    public init(id: String = UUID().uuidString, date: Date, odometerKm: Double,
                liters: Double, pricePerLiter: Double? = nil, totalCost: Double? = nil,
                isFull: Bool = true, note: String = "") {
        self.id = id
        self.date = date
        self.odometerKm = odometerKm
        self.liters = liters
        self.pricePerLiter = pricePerLiter
        self.totalCost = totalCost
        self.isFull = isFull
        self.note = note
    }

    /// 本段油耗 L/100km（与上一条加满记录对比估算，数据不足时返回 nil）
    public func consumption(since previous: FuelRecord?) -> Double? {
        guard let previous, previous.isFull, isFull,
              odometerKm > previous.odometerKm else { return nil }
        let distance = odometerKm - previous.odometerKm
        guard distance > 1 else { return nil }
        // 两次加满之间的总加油量近似为两次加油量之和（上一次油箱已清空计量）
        let totalLiters = liters + previous.liters
        return totalLiters / distance * 100
    }
}

/// 维保记录
public struct MaintenanceRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    /// 保养日期
    public var date: Date
    /// 保养时里程 km
    public var odometerKm: Double
    /// 项目（如：更换机油机滤）
    public var item: String
    /// 花费 元（可选）
    public var cost: Double?
    /// 备注
    public var note: String
    /// 下次提醒里程 km（可选，0 表示不设置）
    public var nextOdometerKm: Double?
    /// 下次提醒日期（可选）
    public var nextDate: Date?

    public init(id: String = UUID().uuidString, date: Date, odometerKm: Double, item: String,
                cost: Double? = nil, note: String = "",
                nextOdometerKm: Double? = nil, nextDate: Date? = nil) {
        self.id = id
        self.date = date
        self.odometerKm = odometerKm
        self.item = item
        self.cost = cost
        self.note = note
        self.nextOdometerKm = nextOdometerKm
        self.nextDate = nextDate
    }

    /// 距离下次保养里程（负数表示已超期；nil 表示未设置）
    public func remainingKm(currentOdometerKm: Double) -> Double? {
        guard let next = nextOdometerKm, next > 0 else { return nil }
        return next - currentOdometerKm
    }
}
