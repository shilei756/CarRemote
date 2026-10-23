import Foundation

// MARK: - 本地设置

/// 仪表盘车型外观（与网页版 CAR_MODELS 一一对应：侧视大图 + 俯视小图 + 油箱容积）
public enum CarModelStyle: String, Codable, CaseIterable, Sendable {
    case yidong = "yidong"                  // 逸动PLUS
    case yidongWhite = "yidong_white"       // 逸动PLUS 白色
    case univ = "univ"                      // UNI-V
    case cs75 = "cs75"                      // CS75PLUS
    case univK = "univ_k"                   // UNI-K
    case cs7520 = "cs75_20"                 // CS75 20款

    /// 展示名（网页版 CAR_MODELS.name）
    public var displayName: String {
        switch self {
        case .yidong: return "逸动PLUS"
        case .yidongWhite: return "逸动PLUS 白色"
        case .univ: return "UNI-V"
        case .cs75: return "CS75PLUS"
        case .univK: return "UNI-K"
        case .cs7520: return "CS75 20款"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .yidong, .yidongWhite: return "car"
        case .univ: return "car.rear"
        case .cs75, .univK, .cs7520: return "car.front"
        }
    }

    /// 侧视大图资源名（网页版 /static/img/*_side.png）
    public var sideImageName: String {
        switch self {
        case .yidong: return "car_yidong"
        case .yidongWhite: return "car_yidong_white"
        case .univ: return "car_univ"
        case .cs75: return "car_cs75plus"
        case .univK: return "car_univ_k"
        case .cs7520: return "car_cs75_20"
        }
    }

    /// 俯视小图资源名（网页版 /static/img/*_top.png，车况卡右侧）
    public var topImageName: String {
        switch self {
        case .yidong: return "car_top_yidong"
        case .yidongWhite: return "car_top_yidong_white"
        case .univ: return "car_top_univ"
        case .cs75: return "car_top_cs75plus"
        case .univK: return "car_top_univ_k"
        case .cs7520: return "car_top_cs75_20"
        }
    }

    /// 是否有内置官方 3D 车模（逸动PLUS 2022，C211，来自长安智慧云控安装包）。
    /// 其他车型后续把对应 glb 放进 Resources/3DModel 并在此登记即可接入。
    public var has3DModel: Bool {
        switch self {
        case .yidong, .yidongWhite: return true
        default: return false
        }
    }

    /// 3D 车模资源名（Bundle 内 glb，不带扩展名；无 3D 车模时为 nil）
    public var model3DName: String? {
        has3DModel ? "EadoPlus2022" : nil
    }

    /// 油箱容积 L（网页版 CAR_MODELS.tank：切换车型时联动油量百分比）
    public var tankCapacityL: Double {
        switch self {
        case .yidong, .yidongWhite: return 53
        case .univ: return 51
        case .cs75, .cs7520: return 58
        case .univK: return 56
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
    /// 首页「快捷控车」4 个按钮的顺序（CarCommand.rawValue，自定义布局）
    public var quickCommands: [String]
    /// 首页「更多控车」指令的顺序
    public var moreCommands: [String]
    /// 首页「更多功能」磁贴的顺序（MoreTool.rawValue）
    public var moreTools: [String]
    /// 被隐藏（屏蔽）的项：不在主界面显示。键为对应 rawValue，三类互不相通。
    public var hiddenQuickCommands: Set<String>
    public var hiddenMoreCommands: Set<String>
    public var hiddenTools: Set<String>
    /// 油箱总容量（升），用于油量百分比/进度条
    public var tankCapacityL: Double

    private enum CodingKeys: String, CodingKey {
        case confirmGateCommands, siriEnabledCommands, siriMasterEnabled,
             carModelStyle, clubNick, clubAvatar, widgetCommands,
             quickCommands, moreCommands, moreTools,
             hiddenQuickCommands, hiddenMoreCommands, hiddenTools,
             tankCapacityL
    }

    public init(confirmGateCommands: Set<String>,
                siriEnabledCommands: Set<String>,
                siriMasterEnabled: Bool = true,
                carModelStyle: CarModelStyle,
                clubNick: String,
                clubAvatar: String,
                widgetCommands: [String] = CarModelStyle.defaultWidgetCommands,
                quickCommands: [String] = CarCommand.primaryCommands.map { $0.rawValue },
                moreCommands: [String] = CarCommand.extraCommands.map { $0.rawValue },
                moreTools: [String] = MoreTool.defaultOrder.map { $0.rawValue },
                hiddenQuickCommands: Set<String> = [],
                hiddenMoreCommands: Set<String> = [],
                hiddenTools: Set<String> = [],
                tankCapacityL: Double = 50) {
        self.confirmGateCommands = confirmGateCommands
        self.siriEnabledCommands = siriEnabledCommands
        self.siriMasterEnabled = siriMasterEnabled
        self.carModelStyle = carModelStyle
        self.clubNick = clubNick
        self.clubAvatar = clubAvatar
        self.widgetCommands = widgetCommands
        self.quickCommands = quickCommands
        self.moreCommands = moreCommands
        self.moreTools = moreTools
        self.hiddenQuickCommands = hiddenQuickCommands
        self.hiddenMoreCommands = hiddenMoreCommands
        self.hiddenTools = hiddenTools
        self.tankCapacityL = tankCapacityL
    }

    /// 旧数据兼容解码：新增字段缺省时给默认值，避免老用户设置丢失
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        confirmGateCommands = try container.decodeIfPresent(Set<String>.self, forKey: .confirmGateCommands) ?? []
        siriEnabledCommands = try container.decodeIfPresent(Set<String>.self, forKey: .siriEnabledCommands)
            ?? Set(CarCommand.allCases.map { $0.rawValue })
        siriMasterEnabled = try container.decodeIfPresent(Bool.self, forKey: .siriMasterEnabled) ?? true
        carModelStyle = try container.decodeIfPresent(CarModelStyle.self, forKey: .carModelStyle) ?? .yidong
        clubNick = try container.decodeIfPresent(String.self, forKey: .clubNick) ?? ""
        clubAvatar = try container.decodeIfPresent(String.self, forKey: .clubAvatar) ?? ""
        widgetCommands = try container.decodeIfPresent([String].self, forKey: .widgetCommands)
            ?? CarModelStyle.defaultWidgetCommands
        quickCommands = try container.decodeIfPresent([String].self, forKey: .quickCommands)
            ?? CarCommand.primaryCommands.map { $0.rawValue }
        moreCommands = try container.decodeIfPresent([String].self, forKey: .moreCommands)
            ?? CarCommand.extraCommands.map { $0.rawValue }
        moreTools = try container.decodeIfPresent([String].self, forKey: .moreTools)
            ?? MoreTool.defaultOrder.map { $0.rawValue }
        hiddenQuickCommands = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenQuickCommands) ?? []
        hiddenMoreCommands = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenMoreCommands) ?? []
        hiddenTools = try container.decodeIfPresent(Set<String>.self, forKey: .hiddenTools) ?? []
        tankCapacityL = try container.decodeIfPresent(Double.self, forKey: .tankCapacityL) ?? 50
    }

    // MARK: 自定义顺序的解析（含补齐/过滤非法值，保证渲染永远有内容）

    /// 快捷控车按钮（按自定义顺序，缺省/非法回收为默认集合）
    public var orderedQuickCommands: [CarCommand] {
        let parsed = quickCommands.compactMap { CarCommand(rawValue: $0) }
        let unique = parsed.reduce(into: [CarCommand]()) { result, cmd in
            if !result.contains(cmd) { result.append(cmd) }
        }
        return unique.isEmpty ? CarCommand.primaryCommands : unique
    }

    /// 更多控车指令（按自定义顺序）
    public var orderedMoreCommands: [CarCommand] {
        let parsed = moreCommands.compactMap { CarCommand(rawValue: $0) }
        let unique = parsed.reduce(into: [CarCommand]()) { result, cmd in
            if !result.contains(cmd) { result.append(cmd) }
        }
        return unique.isEmpty ? CarCommand.extraCommands : unique
    }

    /// 更多功能磁贴（按自定义顺序，只保留可见项）
    public var orderedMoreTools: [MoreTool] {
        let parsed = moreTools.compactMap { MoreTool(rawValue: $0) }
        let unique = parsed.reduce(into: [MoreTool]()) { result, tool in
            if !result.contains(tool) { result.append(tool) }
        }
        // 补齐缺失项（新增磁贴后老用户也能看到）
        var merged = unique
        for tool in MoreTool.defaultOrder where !merged.contains(tool) {
            merged.append(tool)
        }
        return merged
    }

    /// 快捷控车按钮（已剔除被隐藏项，仅用于主界面渲染）
    public var visibleQuickCommands: [CarCommand] {
        orderedQuickCommands.filter { !hiddenQuickCommands.contains($0.rawValue) }
    }

    /// 更多控车指令（已剔除被隐藏项，仅用于主界面渲染）
    public var visibleMoreCommands: [CarCommand] {
        orderedMoreCommands.filter { !hiddenMoreCommands.contains($0.rawValue) }
    }

    /// 更多功能磁贴（已剔除被隐藏项，仅用于主界面渲染）
    public var visibleMoreTools: [MoreTool] {
        orderedMoreTools.filter { !hiddenTools.contains($0.rawValue) }
    }

    public static let `default` = AppSettings(
        confirmGateCommands: ["UnLockDoor", "LockDoor", "OpenEngine", "CloseEngine"],
        siriEnabledCommands: Set(CarCommand.allCases.map { $0.rawValue }),
        siriMasterEnabled: true,
        carModelStyle: .yidong,
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

    // MARK: 屏蔽（隐藏）开关：被隐藏项不在主界面显示

    public mutating func toggleHiddenQuick(command: CarCommand) {
        if hiddenQuickCommands.contains(command.rawValue) {
            hiddenQuickCommands.remove(command.rawValue)
        } else {
            hiddenQuickCommands.insert(command.rawValue)
        }
    }

    public mutating func toggleHiddenMore(command: CarCommand) {
        if hiddenMoreCommands.contains(command.rawValue) {
            hiddenMoreCommands.remove(command.rawValue)
        } else {
            hiddenMoreCommands.insert(command.rawValue)
        }
    }

    public mutating func toggleHiddenTool(tool: MoreTool) {
        if hiddenTools.contains(tool.rawValue) {
            hiddenTools.remove(tool.rawValue)
        } else {
            hiddenTools.insert(tool.rawValue)
        }
    }

    /// 一键恢复全部显示（清除所有隐藏项，配合「恢复默认」使用）
    public mutating func showAllFeatures() {
        hiddenQuickCommands.removeAll()
        hiddenMoreCommands.removeAll()
        hiddenTools.removeAll()
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
    /// 小组件按钮配置（随快照共享：重签环境下独立通道可能失效，快照通道已验证可用）
    public var widgetCommands: [String]?

    public init(carName: String, status: CarStatus, widgetCommands: [String]? = nil) {
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
        self.widgetCommands = widgetCommands
    }

    public init(carName: String, widgetCommands: [String]? = nil) {
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
        self.widgetCommands = widgetCommands
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
        static let acOpenRefreshToken = "carremote.acOpenRefreshToken"
        static let acLastTemp = "carremote.acLastTemp"
        static let serverBaseURL = "carremote.serverBaseURL"
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
        if let creds = loadCredentialsFromDefaults() {
            return creds
        }
        // 第三通道：App Group 容器目录文件（个别重签环境下 UserDefaults 失效时兜底）
        if let data = containerFileData(Key.credentials),
           let creds = try? JSONDecoder().decode(Credentials.self, from: data) {
            return creds
        }
        return nil
    }

    public static func saveCredentials(_ credentials: Credentials?) {
        if let credentials,
           let data = try? JSONEncoder().encode(credentials),
           let json = String(data: data, encoding: .utf8) {
            KeychainStore.set(json, forKey: Key.credentials)
        } else {
            KeychainStore.remove(Key.credentials)
        }
        // 兜底副本 1：App Group UserDefaults
        if let credentials,
           let data = try? JSONEncoder().encode(credentials) {
            defaults?.set(data, forKey: Key.credentials)
        } else {
            defaults?.removeObject(forKey: Key.credentials)
        }
        // 兜底副本 2：App Group 容器目录文件
        if let credentials,
           let data = try? JSONEncoder().encode(credentials) {
            writeContainerFile(data, forKey: Key.credentials)
        } else {
            writeContainerFile(nil, forKey: Key.credentials)
        }
    }

    private static func loadCredentialsFromDefaults() -> Credentials? {
        guard let data = defaults?.data(forKey: Key.credentials) else { return nil }
        return try? JSONDecoder().decode(Credentials.self, from: data)
    }

    /// App Group 容器目录文件读写（UserDefaults 读不到时的第二兜底）
    private static func containerURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: APIConfig.appGroupIdentifier)?
            .appendingPathComponent("carremote_shared", isDirectory: true)
    }

    private static func writeContainerFile(_ data: Data?, forKey key: String) {
        guard let dir = containerURL() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(key + ".bin")
        if let data {
            try? data.write(to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func containerFileData(_ key: String) -> Data? {
        guard let url = containerURL()?.appendingPathComponent(key + ".bin") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// 凭据三条通道的诊断（小组件「未登录」界面显示，用于远程定位数据通道断点）
    public static func credentialsDiagnostics() -> String {
        let kc = KeychainStore.get(Key.credentials) != nil
        let dg = defaults?.data(forKey: Key.credentials) != nil
        let cf = containerFileData(Key.credentials) != nil
        return "诊断 钥匙串\(kc ? "✓" : "✗") 共享存储\(dg ? "✓" : "✗") 容器文件\(cf ? "✓" : "✗")"
    }

    // MARK: 设置（App Group 为主，Keychain/容器文件镜像兜底——小组件读按钮配置用）

    public static func loadSettings() -> AppSettings {
        if let data = defaults?.data(forKey: Key.settings),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        if let data = containerFileData(Key.settings),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        if let json = KeychainStore.get(Key.settings),
           let data = json.data(using: .utf8),
           let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
            return settings
        }
        return .default
    }

    public static func saveSettings(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults?.set(data, forKey: Key.settings)
        writeContainerFile(data, forKey: Key.settings)
        if let json = String(data: data, encoding: .utf8) {
            KeychainStore.set(json, forKey: Key.settings)
        }
    }

    // MARK: 车况快照（App Group 为主，Keychain/容器文件镜像兜底——重签环境下 App Group 可能失效）

    public static func loadStatusSnapshot() -> StatusSnapshot? {
        if let data = defaults?.data(forKey: Key.statusSnapshot),
           let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: data) {
            return snapshot
        }
        if let data = containerFileData(Key.statusSnapshot),
           let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: data) {
            return snapshot
        }
        if let json = KeychainStore.get(Key.statusSnapshot),
           let data = json.data(using: .utf8),
           let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: data) {
            return snapshot
        }
        return nil
    }

    public static func saveStatusSnapshot(_ snapshot: StatusSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: Key.statusSnapshot)
        writeContainerFile(data, forKey: Key.statusSnapshot)
        if let json = String(data: data, encoding: .utf8) {
            KeychainStore.set(json, forKey: Key.statusSnapshot)
        }
    }

    /// 退出登录时清空快照（小组件展示「未登录」）
    public static func clearStatusSnapshot() {
        defaults?.removeObject(forKey: Key.statusSnapshot)
        writeContainerFile(nil, forKey: Key.statusSnapshot)
        KeychainStore.remove(Key.statusSnapshot)
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

    /// 自定义服务器地址（换域名时站主在设置里手填，免发版）。空 = 用默认地址。
    public static func loadServerBaseURL() -> String? {
        let t = defaults?.string(forKey: Key.serverBaseURL)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !t.isEmpty else { return nil }
        // 规范化：补协议、去末尾斜杠，避免拼 URL 出错
        var url = t
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    public static func saveServerBaseURL(_ url: String?) {
        defaults?.set(url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                      forKey: Key.serverBaseURL)
    }

    /// 开放平台最新 refresh_token（oauth 每次刷新都会轮换，必须存回本地，
    /// 下次优先用最新的，否则长安会返回降级 token：scope 只剩 car_info/user）
    public static func loadACOpenRefreshToken() -> String? {
        let t = defaults?.string(forKey: Key.acOpenRefreshToken) ?? ""
        return t.isEmpty ? nil : t
    }

    public static func saveACOpenRefreshToken(_ token: String?) {
        defaults?.set(token ?? "", forKey: Key.acOpenRefreshToken)
    }

    /// 上次开空调选择的温度（网页版 localStorage ac_last_temp，16~32 有效）
    public static func loadACLastTemp() -> Int? {
        guard let t = defaults?.integer(forKey: Key.acLastTemp), (16...32).contains(t) else { return nil }
        return t
    }

    public static func saveACLastTemp(_ temp: Int?) {
        if let temp, (16...32).contains(temp) {
            defaults?.set(temp, forKey: Key.acLastTemp)
        } else {
            defaults?.removeObject(forKey: Key.acLastTemp)
        }
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
