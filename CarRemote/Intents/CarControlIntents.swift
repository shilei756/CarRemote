import AppIntents
import Foundation
import CarCore

// =============================================================
// 控车指令 · 一条指令一个 Intent（快捷指令里可单独拖拽、单独命名、单独上锁屏）
//
// 设计原则：
// 1) 每个功能都是独立动作，不依赖「控制车辆」这条兼容入口；
// 2) openAppWhenRun = false —— 在后台把指令发给车机，不弹 App；
// 3) 开锁 / 闭锁 / 点火 / 熄火属高危，执行前要一次系统确认（语音或弹窗）。
// =============================================================

// MARK: - 开锁

@available(iOS 16.0, *)
struct UnlockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "解锁车辆"
    static var description: IntentDescription = "向你的爱车发送解锁指令"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .unlockDoor)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 闭锁

@available(iOS 16.0, *)
struct LockCarIntent: AppIntent {
    static var title: LocalizedStringResource = "锁定车辆"
    static var description: IntentDescription = "向你的爱车发送闭锁指令"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .lockDoor)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 一键闭锁（车门 + 全部车窗）

@available(iOS 16.0, *)
struct OneKeyLockIntent: AppIntent {
    static var title: LocalizedStringResource = "一键闭锁"
    static var description: IntentDescription = "锁车门后自动关闭全部车窗，离车时一步到位"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 与网页版 doLockAll 一致：先闭锁，约 4.5 秒后再升窗，单次调用完成两件事
        let outcome = await CarIntentRunner.run(command: .oneKeyLock)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 闪灯

@available(iOS 16.0, *)
struct FlashLightsIntent: AppIntent {
    static var title: LocalizedStringResource = "闪灯"
    static var description: IntentDescription = "让车辆闪灯，便于寻车"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .flashLight)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 鸣笛

@available(iOS 16.0, *)
struct HonkHornIntent: AppIntent {
    static var title: LocalizedStringResource = "鸣笛"
    static var description: IntentDescription = "让车辆鸣笛，便于寻车"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .whistle)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 寻车（闪灯 + 鸣笛）

@available(iOS 16.0, *)
struct FindCarIntent: AppIntent {
    static var title: LocalizedStringResource = "寻车"
    static var description: IntentDescription = "让车辆闪灯鸣笛，帮你找到停车位置"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .remoteSearchCar)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 远程点火（高危）

@available(iOS 16.0, *)
struct StartEngineIntent: AppIntent {
    static var title: LocalizedStringResource = "远程点火"
    static var description: IntentDescription = "远程启动发动机（高危操作，执行前需确认）"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 高危操作：Siri 语音确认后执行（iOS 18+ 用新版 API，16/17 用废弃但可用的旧 API）
        try await confirmDangerous(IntentDialog("确认要远程启动发动机吗？"))
        let outcome = await CarIntentRunner.run(command: .openEngine)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 远程熄火（高危）

@available(iOS 16.0, *)
struct StopEngineIntent: AppIntent {
    static var title: LocalizedStringResource = "远程熄火"
    static var description: IntentDescription = "远程关闭发动机（高危操作，执行前需确认）"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await confirmDangerous(IntentDialog("确认要远程关闭发动机吗？"))
        let outcome = await CarIntentRunner.run(command: .closeEngine)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 降下车窗

@available(iOS 16.0, *)
struct OpenWindowsIntent: AppIntent {
    static var title: LocalizedStringResource = "降下车窗"
    static var description: IntentDescription = "远程降下全部车窗，上车前先散热散味"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .openWindow)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 关闭车窗

@available(iOS 16.0, *)
struct CloseWindowsIntent: AppIntent {
    static var title: LocalizedStringResource = "关闭车窗"
    static var description: IntentDescription = "关闭所有车窗"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .closeWindow)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 车窗留缝

@available(iOS 16.0, *)
struct WindowSlitIntent: AppIntent {
    static var title: LocalizedStringResource = "车窗留缝"
    static var description: IntentDescription = "四窗留一条缝，夏天停车通风又防雨"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .windowSlit)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 关闭天窗

@available(iOS 16.0, *)
struct CloseSunroofIntent: AppIntent {
    static var title: LocalizedStringResource = "关闭天窗"
    static var description: IntentDescription = "远程关闭天窗"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .closeDormer)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 天窗上翘

@available(iOS 16.0, *)
struct TiltSunroofIntent: AppIntent {
    static var title: LocalizedStringResource = "天窗上翘"
    static var description: IntentDescription = "天窗后部翘起通风，比全开更防雨"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .skyWindowLiftUp)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 开 / 关空调

@available(iOS 16.0, *)
struct OpenACIntent: AppIntent {
    static var title: LocalizedStringResource = "打开空调"
    static var description: IntentDescription = "远程开启空调（按车机上次设定温度）"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .openAir)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

@available(iOS 16.0, *)
struct CloseACIntent: AppIntent {
    static var title: LocalizedStringResource = "关闭空调"
    static var description: IntentDescription = "远程关闭空调"
    static var openAppWhenRun: Bool = false

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await CarIntentRunner.run(command: .closeAir)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}

// MARK: - 开空调并设定温度

/// 带温度参数的空调指令：温度可以是常量，也可以接「变量 / 数字 / 天气」，
/// 例如「今天 35℃ → 开空调设 24℃」的自动化。
@available(iOS 16.0, *)
struct SetACTemperatureIntent: AppIntent {
    static var title: LocalizedStringResource = "打开空调并设定温度"
    static var description: IntentDescription = "远程开启空调并指定 16~32 摄氏度的目标温度（车机按 1℃ 取整）"
    static var openAppWhenRun: Bool = false

    @Parameter(title: "温度（摄氏度）")
    var temperature: Int

    init() {}

    init(temperature: Int) {
        self.temperature = temperature
    }

    static var parameterSummary: some ParameterSummary {
        Summary("打开空调，设定 \(\.$temperature) 摄氏度")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // 车机只接受 16~32 的整数：越界夹紧，不报错打断自动化
        let target = min(32, max(16, temperature))
        let outcome = await CarIntentRunner.run(command: .openAir, temperature: target)
        return .result(dialog: IntentDialog(stringLiteral: outcome.speech))
    }
}
