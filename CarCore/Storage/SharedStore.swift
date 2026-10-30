import Foundation

// MARK: - 本地设置

/// 仪表盘车型外观（与网页版 CAR_MODELS 一一对应：侧视大图 + 俯视小图 + 油箱容积）
public enum CarModelStyle: String, Codable, CaseIterable, Sendable {
    case yidong = "yidong"                  // 逸动PLUS
    case yidongWhite = "yidong_white"       // 逸动PLUS 白色
    case yidong3 = "yidong3"                // 三代逸动（网站新增 2D 车模，增加不替换）
    case univ = "univ"                      // UNI-V
    case cs75 = "cs75"                      // CS75PLUS
    case univK = "univ_k"                   // UNI-K
    case cs7520 = "cs75_20"                 // CS75 20款
    case cs75Black = "cs75_black"            // CS75PLUS 黑色（用户网站新增 2D 图，增加不替换）

    /// 「我的爱车」GLB 官方车模 ↔ 现有 2D 车型映射（能对应上的都接 3D，其余车型已删除）：
    ///   c211=逸动PLUS（已有官方 .rk 全件模，保留联动更佳）  c281=UNI-V
    ///   c589=三代逸动   s311=CS75PLUS 二代   s311mca1phev=CS75PLUS 三代（无对应 2D，已删）
    ///   cd569=CS35PLUS / s202=UNI-T / s203=CS55PLUS / c236 / c281phev / s311mca：无 2D 对应，已删
    public static let glbModelNames: [CarModelStyle: String] = [
        .univ: "c281",          // UNI-V → C281 官方 GLB（门/窗/尾门/天窗/车轮全联动）
        .yidong3: "c589",       // 三代逸动 → C589 官方 GLB
        .cs75: "s311",          // CS75PLUS → S311 二代官方 GLB
        .cs75Black: "s311",     // CS75PLUS 黑色（同 S311 车身）
        .cs7520: "s311"         // CS75 20款（暂以二代模顶替，一代模暂缺）
    ]

    /// 展示名（网页版 CAR_MODELS.name）
    public var displayName: String {
        switch self {
        case .yidong: return "逸动PLUS"
        case .yidongWhite: return "逸动PLUS 白色"
        case .yidong3: return "三代逸动"
        case .univ: return "UNI-V"
        case .cs75: return "CS75PLUS"
        case .univK: return "UNI-K"
        case .cs7520: return "CS75 20款"
        case .cs75Black: return "CS75 黑色"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .yidong, .yidongWhite, .yidong3: return "car"
        case .univ: return "car.rear"
        case .cs75, .cs75Black, .univK, .cs7520: return "car.front"
        }
    }

    /// 侧视大图资源名（网页版 /static/img/*_side.png）
    public var sideImageName: String {
        switch self {
        case .yidong: return "car_yidong"
        case .yidongWhite: return "car_yidong_white"
        case .yidong3: return "car_yidong3"
        case .univ: return "car_univ"
        case .cs75: return "car_cs75plus"
        case .univK: return "car_univ_k"
        case .cs7520: return "car_cs75_20"
        case .cs75Black: return "car_cs75_black"
        }
    }

    /// 俯视小图资源名（网页版 /static/img/*_top.png，车况卡右侧）
    public var topImageName: String {
        switch self {
        case .yidong: return "car_top_yidong"
        case .yidongWhite: return "car_top_yidong_white"
        case .yidong3: return "car_top_yidong3"
        case .univ: return "car_top_univ"
        case .cs75: return "car_top_cs75plus"
        case .univK: return "car_top_univ_k"
        case .cs7520: return "car_top_cs75_20"
        case .cs75Black: return "car_top_cs75_black"
        }
    }

    /// 是否有内置官方 3D 车模（.rk 全件模或「我的爱车」GLB 官方模）
    public var has3DModel: Bool {
        guard #available(iOS 15.0, *) else { return false }
        return model3DName != nil
    }

    /// 3D 车模资源名：
    ///   - "xxx.glb" →「我的爱车」GLB 官方模（GLBCarModelLoader 解析，门窗/尾门/天窗/车轮联动）
    ///   - 其余     → 智慧云控 .rk 官方全件模（Car3DView .rk 管线）
    public var model3DName: String? {
        switch self {
        case .yidong: return "EadoPlus2022Gray"   // C211 全部件模 · 钛光银灰（1.1.4-b110 用户指定，色值 #C6C6C6 对齐官网）
        case .yidongWhite: return "EadoPlus2022"  // C211 全部件模 · 白色款
        default:
            guard let glb = Self.glbModelNames[self] else { return nil }
            return "\(glb).glb"
        }
    }

    /// 油箱容积 L（网页版 CAR_MODELS.tank：切换车型时联动油量百分比）
    public var tankCapacityL: Double {
        switch self {
        case .yidong, .yidongWhite, .yidong3: return 53
        case .univ: return 51
        case .cs75, .cs75Black, .cs7520: return 58
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
    /// 控车页 3D 车模总开关（逸动PLUS 2022 官方车模；关闭后显示 2D 车图）。
    /// 默认开启；若设备上 3D 渲染异常，可在此一键回退。
    public var car3DEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case confirmGateCommands, siriEnabledCommands, siriMasterEnabled,
             carModelStyle, clubNick, clubAvatar, widgetCommands,
             quickCommands, moreCommands, moreTools,
             hiddenQuickCommands, hiddenMoreCommands, hiddenTools,
             tankCapacityL, car3DEnabled
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
                tankCapacityL: Double = 50,
                car3DEnabled: Bool = true) {
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
        self.car3DEnabled = car3DEnabled
    }

    /// 旧数据兼容解码：新增字段缺省时给默认值，避免老用户设置丢失
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        confirmGateCommands = try container.decodeIfPresent(Set<String>.self, forKey: .confirmGateCommands) ?? []
        siriEnabledCommands = try container.decodeIfPresent(Set<String>.self, forKey: .siriEnabledCommands)
            ?? Set(CarCommand.allCases.map { $0.rawValue })
        siriMasterEnabled = try container.decodeIfPresent(Bool.self, forKey: .siriMasterEnabled) ?? true
        // 车型按 String 解码 + 旧值迁移：1.5.1 删除了 12 个「车模库」独立车型 case，
        // 老用户若存过 c211/c281/c589/s311 等旧值，迁移到对应的现有车型，避免解码失败丢整套设置
        let styleRaw = try container.decodeIfPresent(String.self, forKey: .carModelStyle) ?? ""
        let migratedStyles = ["c211": CarModelStyle.yidong, "c281": .univ,
                              "c589": .yidong3, "s311": .cs75]
        carModelStyle = CarModelStyle(rawValue: styleRaw) ?? migratedStyles[styleRaw] ?? .yidong
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
        car3DEnabled = try container.decodeIfPresent(Bool.self, forKey: .car3DEnabled) ?? true
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
        static let customWallpaper = "carremote.customWallpaper"
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: APIConfig.appGroupIdentifier)
    }

    /// 全部候选共享存储：工程默认组 + 重签描述文件动态发现的组。
    /// 读取时按顺序试到命中；写入时全部落笔（无权限的组静默失败，无害）。
    private static var allDefaults: [UserDefaults] {
        ResignCompat.candidateAppGroups().compactMap { UserDefaults(suiteName: $0) }
    }

    // MARK: 凭据（Keychain 为主，App Group 兜底——小组件在两种环境下都能读到）

    public static func loadCredentials() -> Credentials? {
        if let json = KeychainStore.get(Key.credentials),
           let data = json.data(using: .utf8),
           let creds = try? JSONDecoder().decode(Credentials.self, from: data) {
            return creds
        }
        for d in allDefaults {
            if let data = d.data(forKey: Key.credentials),
               let creds = try? JSONDecoder().decode(Credentials.self, from: data) {
                return creds
            }
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
        // 兜底副本 1：App Group UserDefaults（全部候选组都写，重签环境哪个有权限哪个生效）
        if let credentials, let data = try? JSONEncoder().encode(credentials) {
            allDefaults.forEach { $0.set(data, forKey: Key.credentials) }
        } else {
            allDefaults.forEach { $0.removeObject(forKey: Key.credentials) }
        }
        // 兜底副本 2：App Group 容器目录文件
        if let credentials, let data = try? JSONEncoder().encode(credentials) {
            writeContainerFile(data, forKey: Key.credentials)
        } else {
            writeContainerFile(nil, forKey: Key.credentials)
        }
    }

    /// App Group 容器目录文件读写（UserDefaults 读不到时的第二兜底）。
    /// 遍历全部候选组：默认组 + 重签描述文件发现的组（读：命中即回；写：全写）。
    private static func containerURLs() -> [URL] {
        ResignCompat.candidateAppGroups().compactMap {
            FileManager.default
                .containerURL(forSecurityApplicationGroupIdentifier: $0)?
                .appendingPathComponent("carremote_shared", isDirectory: true)
        }
    }

    private static func writeContainerFile(_ data: Data?, forKey key: String) {
        for dir in containerURLs() {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent(key + ".bin")
            if let data {
                try? data.write(to: url)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func containerFileData(_ key: String) -> Data? {
        for dir in containerURLs() {
            let url = dir.appendingPathComponent(key + ".bin")
            if let data = try? Data(contentsOf: url) { return data }
        }
        return nil
    }

    /// 凭据三条通道的诊断（小组件「未登录」界面与 App 设置页显示，远程定位数据通道断点）。
    /// 重签环境下附带动发现的签名组信息，便于确认重签平台是否开通了 App Group。
    public static func credentialsDiagnostics() -> String {
        let kc = KeychainStore.get(Key.credentials) != nil
        let dg = allDefaults.contains { $0.data(forKey: Key.credentials) != nil }
        let cf = containerFileData(Key.credentials) != nil
        let info = ResignCompat.resignInfo()
        var extra = ""
        if info.profileFound {
            let groups = info.appGroups
            if groups.isEmpty {
                extra = " · 重签未含App组"
            } else if !groups.contains(APIConfig.appGroupIdentifier) {
                extra = " · 签名组\(groups.count)个:" + groups.prefix(2).joined(separator: ",")
            }
        }
        return "诊断 钥匙串\(kc ? "✓" : "✗") 共享存储\(dg ? "✓" : "✗") 容器文件\(cf ? "✓" : "✗")\(extra)"
    }

    /// 小组件数据通道完整诊断报告（App 设置页「小组件诊断」展示）。
    /// 区分两层问题：
    /// 1. 权限层——重签描述文件里有没有声明 App Group / 钥匙串组（决定通道能不能用）；
    /// 2. 数据层——凭据现在能不能读到（决定小组件显示什么）。
    public static func widgetChannelReport() -> String {
        var lines: [String] = []
        let info = ResignCompat.resignInfo()

        // 1) 签名环境
        if info.profileFound {
            lines.append("签名环境：重签描述文件 ✓ 已解析")
        } else {
            lines.append("签名环境：未发现描述文件（App Store 正式包）")
        }

        // 2) App Group 权限（以描述文件声明为准——未声明的组跨进程必然不通）
        if info.profileFound {
            if info.appGroups.isEmpty {
                lines.append("App Group：✗ 重签时未声明（共享存储/容器文件通道失效）")
            } else {
                for g in info.appGroups {
                    let tag = (g == APIConfig.appGroupIdentifier) ? "（工程默认）" : "（重签分配）"
                    lines.append("App Group：✓ \(g)\(tag)")
                }
                if !info.appGroups.contains(APIConfig.appGroupIdentifier) {
                    lines.append("提示：默认组被替换，已自动改用重签组读写 ✓")
                }
            }
            // 3) 钥匙串组
            if info.keychainGroups.isEmpty {
                lines.append("钥匙串组：✗ 重签时未声明（跨进程钥匙串失效，退回各自独立钥匙串）")
            } else {
                for g in info.keychainGroups {
                    lines.append("钥匙串组：✓ \(g)")
                }
            }
        }

        // 4) 钥匙串写入能力（进程内可实测）
        let probe = "carremote.diag.\(UUID().uuidString)"
        KeychainStore.set("1", forKey: probe)
        let kcOK = KeychainStore.get(probe) != nil
        KeychainStore.remove(probe)
        lines.append("钥匙串写入：\(kcOK ? "✓" : "✗")")

        // 5) 凭据可读性（数据层）
        let creds = loadCredentials() != nil
        lines.append("登录凭据：\(creds ? "✓ 可读取" : "✗ 读不到")")
        let snap = loadStatusSnapshot() != nil
        lines.append("车况快照：\(snap ? "✓ 可读取" : "✗ 暂无（App 刷新车况后写入）")")
        return lines.joined(separator: "\n")
    }

    // MARK: 设置（App Group 为主，Keychain/容器文件镜像兜底——小组件读按钮配置用）

    public static func loadSettings() -> AppSettings {
        for d in allDefaults {
            if let data = d.data(forKey: Key.settings),
               let settings = try? JSONDecoder().decode(AppSettings.self, from: data) {
                return settings
            }
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
        allDefaults.forEach { $0.set(data, forKey: Key.settings) }
        writeContainerFile(data, forKey: Key.settings)
        if let json = String(data: data, encoding: .utf8) {
            KeychainStore.set(json, forKey: Key.settings)
        }
    }

    // MARK: 车况快照（App Group 为主，Keychain/容器文件镜像兜底——重签环境下 App Group 可能失效）

    public static func loadStatusSnapshot() -> StatusSnapshot? {
        for d in allDefaults {
            if let data = d.data(forKey: Key.statusSnapshot),
               let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: data) {
                return snapshot
            }
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
        allDefaults.forEach { $0.set(data, forKey: Key.statusSnapshot) }
        writeContainerFile(data, forKey: Key.statusSnapshot)
        if let json = String(data: data, encoding: .utf8) {
            KeychainStore.set(json, forKey: Key.statusSnapshot)
        }
    }

    /// 退出登录时清空快照（小组件展示「未登录」）
    public static func clearStatusSnapshot() {
        allDefaults.forEach { $0.removeObject(forKey: Key.statusSnapshot) }
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
    /// 小组件进程拉车况也要用，故走多组遍历（重签环境组名可能变化）。
    public static func loadServerBaseURL() -> String? {
        let t = allDefaults.compactMap { $0.string(forKey: Key.serverBaseURL) }
            .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? ""
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // 规范化：补协议、去末尾斜杠，避免拼 URL 出错
        var url = trimmed
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
        }
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    public static func saveServerBaseURL(_ url: String?) {
        let value = url?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        allDefaults.forEach { $0.set(value, forKey: Key.serverBaseURL) }
    }

    /// 开放平台最新 refresh_token（oauth 每次刷新都会轮换，必须存回本地，
    /// 下次优先用最新的，否则长安会返回降级 token：scope 只剩 car_info/user）
    public static func loadACOpenRefreshToken() -> String? {
        let t = allDefaults.compactMap { $0.string(forKey: Key.acOpenRefreshToken) }
            .first { !$0.isEmpty } ?? ""
        return t.isEmpty ? nil : t
    }

    public static func saveACOpenRefreshToken(_ token: String?) {
        let value = token ?? ""
        allDefaults.forEach { $0.set(value, forKey: Key.acOpenRefreshToken) }
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

    /// 自定义壁纸（用户从相册上传的图片 Data；nil = 未设置，走默认背景）。
    /// 大图走容器文件，App Group UserDefaults 镜像一份供小组件读取。
    public static func loadCustomWallpaper() -> Data? {
        if let data = containerFileData(Key.customWallpaper) { return data }
        if let data = allDefaults.compactMap({ $0.data(forKey: Key.customWallpaper) }).first(where: { !$0.isEmpty }) {
            return data
        }
        return defaults?.data(forKey: Key.customWallpaper)
    }

    public static func saveCustomWallpaper(_ data: Data?) {
        writeContainerFile(data, forKey: Key.customWallpaper)
        allDefaults.forEach { $0.set(data, forKey: Key.customWallpaper) }
    }

    public static func loadAppTheme() -> AppTheme {
        // 多组遍历（重签环境下默认组可能失效，对齐其它设置的读取方式）
        guard let raw = allDefaults.compactMap({ $0.string(forKey: Key.appTheme) }).first(where: { !$0.isEmpty }),
              let theme = AppTheme(rawValue: raw) else { return .light }
        return theme
    }

    public static func saveAppTheme(_ theme: AppTheme) {
        allDefaults.forEach { $0.set(theme.rawValue, forKey: Key.appTheme) }
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
