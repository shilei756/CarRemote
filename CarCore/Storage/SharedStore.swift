import Foundation

// MARK: - 本地设置

/// 仪表盘车型外观
public enum CarModelStyle: String, Codable, CaseIterable, Sendable {
    case sedan = "三厢轿车"
    case coupe = "运动轿跑"
    case suv = "智能SUV"

    /// 展示名（真实车型名）
    public var displayName: String {
        switch self {
        case .sedan: return "逸动PLUS"
        case .coupe: return "UNI-V"
        case .suv: return "CS75PLUS"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .sedan: return "car"
        case .coupe: return "car.rear"
        case .suv: return "car.front"
        }
    }

    /// 小组件按钮默认配置（闪灯/开锁/闭锁/鸣笛/寻车）
    public static let defaultWidgetCommands: [String] = [
        CarCommand.flashLight.rawValue,
        CarCommand.unlockDoor.rawValue,
        CarCommand.lockDoor.rawValue,
        CarCommand.whistle.rawValue,
        CarCommand.remoteSearchCar.rawValue
    ]
}

/// App 主题（与网页版夜间模式对应）
public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case light = "浅色"
    case dark = "夜间"
}

/// 神兽主题（网页版 MYTH_THEMES：整套界面换装，白名单授权用户可用）
/// 配色与网页版 html.glass.myth-* CSS 变量一一对应
public enum MythTheme: String, Codable, CaseIterable, Sendable {
    case qinglong = "qinglong"
    case zhuque = "zhuque"
    case qilin = "qilin"
    case baihu = "baihu"

    /// 名称（网页版 name）
    public var name: String {
        switch self {
        case .qinglong: return "青龙"
        case .zhuque: return "朱雀"
        case .qilin: return "麒麟"
        case .baihu: return "白虎"
        }
    }

    /// 副标题（网页版 sub）
    public var subtitle: String {
        switch self {
        case .qinglong: return "苍岚·青碧鎏金"
        case .zhuque: return "丹霞·赤金羽焰"
        case .qilin: return "鎏金·瑞兽献祥"
        case .baihu: return "玄墨·银霜"
        }
    }

    /// 描述（网页版 desc）
    public var desc: String {
        switch self {
        case .qinglong: return "青碧山水为底、鎏金为纹，按键与图标染青碧色，寓意东方青龙守行"
        case .zhuque: return "赤霞羽焰为底、丹金为纹，按键与图标染朱赤色，寓意南方朱雀护佑"
        case .qilin: return "鎏金祥云为底、琥珀为纹，按键与图标染鎏金色，寓意金麒麟踏云献瑞"
        case .baihu: return "玄铁墨灰为底、水墨为纹，按键与图标染墨灰色，寓意西方白虎镇煞辟邪"
        }
    }

    /// 主色（--myth-main）
    public var mainHex: UInt {
        switch self {
        case .qinglong: return 0x0d9488
        case .zhuque: return 0xdc2626
        case .qilin: return 0xb8860b
        case .baihu: return 0x4a4f57
        }
    }

    /// 深色（--myth-deep）
    public var deepHex: UInt {
        switch self {
        case .qinglong: return 0x115e59
        case .zhuque: return 0x991b1b
        case .qilin: return 0x7a5a06
        case .baihu: return 0x23272e
        }
    }

    /// 鎏金（--myth-gold）
    public var goldHex: UInt {
        switch self {
        case .qinglong: return 0xb8860b
        case .zhuque: return 0xd97706
        case .qilin: return 0xe3b23c
        case .baihu: return 0x8a8f98
        }
    }

    /// 背景底色（--bg0）
    public var bgHex: UInt {
        switch self {
        case .qinglong: return 0xe6f2ee
        case .zhuque: return 0xf9ede6
        case .qilin: return 0xfdf8ec
        case .baihu: return 0xececee
        }
    }

    /// 正文色（--txt）
    public var txtHex: UInt {
        switch self {
        case .qinglong: return 0x12352c
        case .zhuque: return 0x3d1a10
        case .qilin: return 0x3a2a08
        case .baihu: return 0x23262b
        }
    }

    /// 次级文字（--muted）
    public var mutedHex: UInt {
        switch self {
        case .qinglong: return 0x3d6459
        case .zhuque: return 0x7c4a38
        case .qilin: return 0x7a5a1e
        case .baihu: return 0x4c5058
        }
    }

    /// 弱文字（--faint）
    public var faintHex: UInt {
        switch self {
        case .qinglong: return 0x6d9188
        case .zhuque: return 0xa5705e
        case .qilin: return 0xa8834a
        case .baihu: return 0x9a9da4
        }
    }

    /// 图腾插画资源名（网页版 /static/vendor/myth/{key}.webp）
    public var imageName: String { "myth_\(rawValue)" }

    /// 预览渐变四色（网页版 openMythPage 的 grad）
    public var previewHexes: [UInt] {
        switch self {
        case .qinglong: return [0xeef7f3, 0x9ed8c8, 0x0d9488, 0xb8860b]
        case .zhuque: return [0xfdf3ec, 0xf5b891, 0xdc2626, 0xd97706]
        case .qilin: return [0xfdf6e6, 0xf0d896, 0xb8860b, 0x7a5a06]
        case .baihu: return [0xf4f8fd, 0xc3d2e6, 0x5b6b83, 0x2b3949]
        }
    }
}

/// App 本地设置（防误触、语音命令开关、车型外观、圈子资料）
public struct AppSettings: Codable, Equatable, Sendable {
    public var confirmGateCommands: Set<String>
    public var siriEnabledCommands: Set<String>
    /// Siri / 快捷指令总开关（重新设计后：一个总闸替代逐条开关）
    public var siriMasterEnabled: Bool
    public var carModelStyle: CarModelStyle
    public var clubNick: String
    public var clubAvatar: String
    /// 桌面小组件的 5 个控车按钮（CarCommand.rawValue，按槽位顺序）
    public var widgetCommands: [String]

    private enum CodingKeys: String, CodingKey {
        case confirmGateCommands, siriEnabledCommands, siriMasterEnabled,
             carModelStyle, clubNick, clubAvatar, widgetCommands
    }

    public init(confirmGateCommands: Set<String>,
                siriEnabledCommands: Set<String>,
                siriMasterEnabled: Bool = true,
                carModelStyle: CarModelStyle,
                clubNick: String,
                clubAvatar: String,
                widgetCommands: [String] = CarModelStyle.defaultWidgetCommands) {
        self.confirmGateCommands = confirmGateCommands
        self.siriEnabledCommands = siriEnabledCommands
        self.siriMasterEnabled = siriMasterEnabled
        self.carModelStyle = carModelStyle
        self.clubNick = clubNick
        self.clubAvatar = clubAvatar
        self.widgetCommands = widgetCommands
    }

    /// 旧数据兼容解码：新增字段缺省时给默认值，避免老用户设置丢失
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        confirmGateCommands = try container.decodeIfPresent(Set<String>.self, forKey: .confirmGateCommands) ?? []
        siriEnabledCommands = try container.decodeIfPresent(Set<String>.self, forKey: .siriEnabledCommands)
            ?? Set(CarCommand.allCases.map { $0.rawValue })
        siriMasterEnabled = try container.decodeIfPresent(Bool.self, forKey: .siriMasterEnabled) ?? true
        carModelStyle = try container.decodeIfPresent(CarModelStyle.self, forKey: .carModelStyle) ?? .sedan
        clubNick = try container.decodeIfPresent(String.self, forKey: .clubNick) ?? ""
        clubAvatar = try container.decodeIfPresent(String.self, forKey: .clubAvatar) ?? ""
        widgetCommands = try container.decodeIfPresent([String].self, forKey: .widgetCommands)
            ?? CarModelStyle.defaultWidgetCommands
    }

    public static let `default` = AppSettings(
        confirmGateCommands: ["UnLockDoor", "LockDoor", "OpenEngine", "CloseEngine"],
        siriEnabledCommands: Set(CarCommand.allCases.map { $0.rawValue }),
        siriMasterEnabled: true,
        carModelStyle: .sedan,
        clubNick: "",
        clubAvatar: ""
    )

    public func needsConfirm(command: CarCommand) -> Bool {
        confirmGateCommands.contains(command.rawValue)
    }

    public func siriAllows(command: CarCommand) -> Bool {
        siriMasterEnabled && siriEnabledCommands.contains(command.rawValue)
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
        static let acActivationExpire = "carremote.acActivationExpire"
        static let mythTheme = "carremote.mythTheme"
        static let customCarName = "carremote.customCarName"
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

    /// 空调开通到期时间（刷新 token 剩余有效期换算，用于「剩余 X 天」展示）
    public static func loadACActivationExpire() -> Date? {
        defaults?.object(forKey: Key.acActivationExpire) as? Date
    }

    public static func saveACActivationExpire(_ date: Date?) {
        defaults?.set(date, forKey: Key.acActivationExpire)
    }

    /// 用户自定义车辆名称（左上角 DIY，空串表示跟随官网原名）
    public static func loadCustomCarName() -> String {
        defaults?.string(forKey: Key.customCarName) ?? ""
    }

    public static func saveCustomCarName(_ name: String) {
        defaults?.set(name, forKey: Key.customCarName)
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

    /// 当前神兽主题（nil = 经典默认；网页版 localStorage myth_theme）
    public static func loadMythTheme() -> MythTheme? {
        guard let raw = defaults?.string(forKey: Key.mythTheme),
              let theme = MythTheme(rawValue: raw) else { return nil }
        return theme
    }

    public static func saveMythTheme(_ theme: MythTheme?) {
        defaults?.set(theme?.rawValue, forKey: Key.mythTheme)
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
