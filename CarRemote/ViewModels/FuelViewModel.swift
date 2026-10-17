import Foundation
import CarCore

/// 油耗统计视图模型（本地记录，与网页版 localStorage 方案对应）
@MainActor
final class FuelViewModel: ObservableObject {

    @Published var records: [FuelRecord] = []
    @Published var errorMessage: String?

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        reload()
    }

    func reload() {
        records = SharedStore.loadFuelRecords()
    }

    // MARK: - 计算属性

    /// 当前总里程（来自车况，缺数据时用最近一次记录）
    var currentOdometerKm: Double? {
        if let odo = appState?.status?.totalOdometerKm { return odo }
        return records.last?.odometerKm
    }

    /// 平均油耗 L/100km（仅统计可估算的相邻满舱记录）
    var averageConsumption: Double? {
        var values: [Double] = []
        for index in records.indices where index > 0 {
            if let value = records[index].consumption(since: records[index - 1]) {
                values.append(value)
            }
        }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// 累计加油花费
    var totalSpend: Double {
        records.compactMap { record -> Double? in
            if let cost = record.totalCost { return cost }
            if let price = record.pricePerLiter { return price * record.liters }
            return nil
        }.reduce(0, +)
    }

    /// 累计加油量
    var totalLiters: Double {
        records.map(\.liters).reduce(0, +)
    }

    /// 最近一次油耗
    var lastConsumption: Double? {
        guard records.count > 1 else { return nil }
        return records[records.count - 1].consumption(since: records[records.count - 2])
    }

    // MARK: - 增删

    func add(_ record: FuelRecord) {
        records.append(record)
        records.sort { $0.odometerKm < $1.odometerKm }
        persist()
    }

    /// 更新一条记录（编辑后按 id 替换并重排）
    func update(_ record: FuelRecord) {
        if let index = records.firstIndex(where: { $0.id == record.id }) {
            records[index] = record
            records.sort { $0.odometerKm < $1.odometerKm }
            persist()
        }
    }

    func delete(_ record: FuelRecord) {
        records.removeAll { $0.id == record.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        SharedStore.saveFuelRecords(records)
    }
}

/// 维保记录视图模型（本地）
@MainActor
final class MaintenanceViewModel: ObservableObject {

    @Published var records: [MaintenanceRecord] = []

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        reload()
    }

    func reload() {
        records = SharedStore.loadMaintenanceRecords()
    }

    var currentOdometerKm: Double? {
        if let odo = appState?.status?.totalOdometerKm { return odo }
        return records.map(\.odometerKm).max()
    }

    /// 临近提醒（30 天内或 500km 内到期，含已超期）
    var upcoming: [MaintenanceRecord] {
        records.filter { record in
            if let remaining = record.remainingKm(currentOdometerKm: currentOdometerKm ?? 0), remaining < 500 {
                return true
            }
            if let nextDate = record.nextDate, nextDate.timeIntervalSinceNow < 30 * 24 * 3600 {
                return true
            }
            return false
        }
    }

    func add(_ record: MaintenanceRecord) {
        records.append(record)
        records.sort { $0.date > $1.date }
        persist()
    }

    func delete(at offsets: IndexSet) {
        records.remove(atOffsets: offsets)
        persist()
    }

    /// 更新最近保养基准（修改上次保养用）
    func updateFirst(_ record: MaintenanceRecord) {
        if !records.isEmpty {
            records[0] = record
        } else {
            records.append(record)
        }
        records.sort { $0.date > $1.date }
        persist()
    }

    private func persist() {
        SharedStore.saveMaintenanceRecords(records)
    }
}
