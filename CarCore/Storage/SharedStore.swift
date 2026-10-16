import Foundation

// MARK: - 本地设置

/// 仪表盘车型外观
public enum CarModelStyle: String, Codable, CaseIterable, Sendable {
    case sedan = "三厢轿车"
    case coupe = "运动轿跑"
    case suv = "智能SUV"

    public var sfSymbol: String {
        switch self {
        case .sedan: return "car"
        case .coupe: return "car.rear"
        case .suv: return "car.front"
        }
    }
}

/// App 主题（与网页版夜间模式对应）
public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case light = "浅色"
    case dark = "夜间"
}

/// App 本地设置（防误触、语音命令开关、车型外观、圈子资料）
public struct AppSettings: Codable, Equatable, Sendable {
    public var confirmGateCommands: Set<String>
    public var siriEnabledCommands: Set<String>
    public var carModelStyle: CarModelStyle
    public var clubNick: String
    public var clubAvatar: String

    public init(confirmGateCommands: Set<String>,
                siriEnabledCommands: Set<String>,
                carModelStyle: CarModelStyle,
                clubNick: String,
                clubAvatar: String) {
        self.confirmGateCommands = confirmGateCommands
        self.siriEnabledCommands = siriEnabledCommands
        self.carModelStyle = carModelStyle
        self.clubNick = clubNick
        self.clubAvatar = clubAvatar
    }

    public static let `default` = AppSettings(
        confirmGateCommands: ["UnLockDoor", "LockDoor", "OpenEngine", "CloseEngine"],
        siriEnabledCommands: Set(CarCommand.allCases.map { $0.rawValue }),
        carModelStyle: .sedan,
        clubNick: "",
        clubAvatar: ""
    )

    public func needsConfirm(command: CarCommand) -> Bool {
        confirmGateCommands.contains(command.rawValue)
    }

    public func siriAllows(command: CarCommand) -> Bool {
        siriEnabledCommands.contains(command.rawValue)
    }

    public mutating func toggleConfirm(command: CarCommand) {
        if confirmGateCommands.contains(command.rawValue) {
            confirmGateCommands.remove(command.rawValue)
        } else {
            confirmGateCommands.insert(command.rawValue)
        }
    }

    public mutating func toggleSiri(command: CarCommand) {
        if siriEnabledCommands.contains(command.rawValue) {
            siriEnabledCommands.remove(command.rawValue)
        } else {
            siriEnabledCommands.insert(command.rawValue)
        }
    }
}

// MARK: - 车况快照（供小组件离线展示）

public struct StatusSnapshot: Codable, Equatable, Sendable {
    public var carName: String
    public var remainingRangeKm: Double?
    public var fuelLeftLiters: Double?
    public var totalOdometerKm: Double?
    public var batteryVoltage: Double?
    public var vehicleTempC: Double?
    public var acTempC: Double?
    public var doorUnlocked: Bool
    public var windowOpen: Bool
    public var sunroofOpen: Bool
    public var engineRunning: Bool
    public var tirePressures: [Double?]
    public var updatedAt: Date

    public init(carName: String, status: CarStatus) {
        self.carName = carName
        self.remainingRangeKm = status.remainingRangeKm
        self.fuelLeftLiters = status.fuelLeftLiters
        self.totalOdometerKm = status.totalOdometerKm
        self.batteryVoltage = status.batteryVoltage
        self.vehicleTempC = status.vehicleTempC
        self.acTempC = status.acTempC
        self.doorUnlocked = status.doorUnlocked
        self.windowOpen = status.windowOpen
        self.sunroofOpen = status.sunroofOpen
        self.engineRunning = status.engineRunning
        self.tirePressures = status.tirePressures.map { $0.valueKPa }
        self.updatedAt = Date()
    }

    public init(carName: String) {
        self.carName = carName
        // 注意：Bool 是非可选类型，不会自动置 nil，必须显式初始化，
        // 否则报 "return from initializer without initializing all stored properties"
        self.remainingRangeKm = nil
        self.fuelLeftLiters = nil
        self.totalOdometerKm = nil
        self.batteryVoltage = nil
        self.vehicleTempC = nil
        self.acTempC = nil
        self.doorUnlocked = false
        self.windowOpen = false
        self.sunroofOpen = false
        self.engineRunning = false
        self.tirePressures = [nil, nil, nil, nil]
        self.updatedAt = .distantPast
    }

    public var summaryText: String {
        var flags = CarStateFlags()
        flags.doorUnlocked = doorUnlocked
        flags.windowOpen = windowOpen
        flags.sunroofOpen = sunroofOpen
        flags.engineRunning = engineRunning
        return flags.summaryText
    }

    public var level: String {
        var flags = CarStateFlags()
        flags.doorUnlocked = doorUnlocked
        flags.windowOpen = windowOpen
        flags.sunroofOpen = sunroofOpen
        flags.engineRunning = engineRunning
        return flags.level
    }

    public var isStale: Bool {
        updatedAt.timeIntervalSinceNow < -6 * 3600
    }
}

// MARK: - 共享存储（App Group UserDefaults）

public enum SharedStore {

    private enum Key {
        static let credentials = "carremote.credentials"
        static let settings = "carremote.settings"
        static let statusSnapshot = "carremote.statusSnapshot"
        static let fuelRecords = "carremote.fuelRecords"
        static let maintenanceRecords = "carremote.maintenanceRecords"
        static let acMode = "carremote.acMode"
        static let appTheme = "carremote.appTheme"
        static let sakuraEnabled = "carremote.sakuraEnabled"
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: APIConfig.appGroupIdentifier)
    }

    // MARK: 凭据（Keychain 为主，App Group 兜底——小组件在两种环境下都能读到）

    public static func loadCredentials() -> Credentials? {
        if let json = KeychainStore.get(Key.credentials),
           let data = json.data(using: .utf8),
           let creds = try? JSONDecoder().decode(Credentials.self, from: data) {
            return creds
        }
        return loadCredentialsFromDefaults()
    }

    public static func saveCredentials(_ credentials: Credentials?) {
        if let credentials,
           let data = try? JSONEncoder().encode(credentials),
           let json = String(data: data, encoding: .utf8) {
            KeychainStore.set(json, forKey: Key.credentials)
        } else {
            KeychainStore.remove(Key.credentials)
        }
        // 兜底副本
        if let credentials,
           let data = try? JSONEncoder().encode(credentials) {
            defaults?.set(data, forKey: Key.credentials)
        } else {
            defaults?.removeObject(forKey: Key.credentials)
        }
    }

    private static func loadCredentialsFromDefaults() -> Credentials? {
        guard let data = defaults?.data(forKey: Key.credentials) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    // MARK: 设置

    public static func loadSettings() -> AppSettings {
        guard let data = defaults?.data(forKey: Key.settings),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return .default
        }
        return settings
    }

    public static func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults?.set(data, forKey: Key.settings)
    }

    // MARK: 车况快照

    public static func loadStatusSnapshot() -> StatusSnapshot? {
        guard let data = defaults?.data(forKey: Key.statusSnapshot) else { return nil }
        return try? JSONDecoder().decode(StatusSnapshot.self, from: data)
    }

    public static func saveStatusSnapshot(_ snapshot: StatusSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: Key.statusSnapshot)
    }

    /// 退出登录时清空快照（小组件展示「未登录」）
    public static func clearStatusSnapshot() {
        defaults?.removeObject(forKey: Key.statusSnapshot)
    }

    // MARK: 油耗记录（本地，与网页版 localStorage 方案对应）

    public static func loadFuelRecords() -> [FuelRecord] {
        guard let data = defaults?.data(forKey: Key.fuelRecords) else { return [] }
        let records = (try? JSONDecoder().decode([FuelRecord].self, from: data)) ?? []
        return records.sorted { $0.odometerKm < $1.odometerKm }
    }

    public static func saveFuelRecords(_ records: [FuelRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults?.set(data, forKey: Key.fuelRecords)
    }

    // MARK: 空调模式 / 主题（独立键存放，避免影响 AppSettings 解码兼容）

    public static func loadACMode() -> ACMode {
        guard let raw = defaults?.string(forKey: Key.acMode),
              let mode = ACMode(rawValue: raw) else { return .new }
        return mode
    }

    public static func saveACMode(_ mode: ACMode) {
        defaults?.set(mode.rawValue, forKey: Key.acMode)
    }

    public static func loadAppTheme() -> AppTheme {
        guard let raw = defaults?.string(forKey: Key.appTheme),
              let theme = AppTheme(rawValue: raw) else { return .light }
        return theme
    }

    public static func saveAppTheme(_ theme: AppTheme) {
        defaults?.set(theme.rawValue, forKey: Key.appTheme)
    }

    /// 樱花飘落背景开关（默认开，兼容旧行为）
    public static func loadSakuraEnabled() -> Bool {
        guard let raw = defaults?.object(forKey: Key.sakuraEnabled) as? Bool else { return true }
        return raw
    }

    public static func saveSakuraEnabled(_ enabled: Bool) {
        defaults?.set(enabled, forKey: Key.sakuraEnabled)
    }

    // MARK: 维保记录（本地）

    public static func loadMaintenanceRecords() -> [MaintenanceRecord] {
        guard let data = defaults?.data(forKey: Key.maintenanceRecords) else { return [] }
        let records = (try? JSONDecoder().decode([MaintenanceRecord].self, from: data)) ?? []
        return records.sorted { $0.date > $1.date }
    }

    public static func saveMaintenanceRecords(_ records: [MaintenanceRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults?.set(data, forKey: Key.maintenanceRecords)
    }
}
