import AppIntents
import CarCore

/// Siri 语音短语（"Hey Siri，用远程控车解锁车辆"）。
///
/// 说明：
/// - Intent 定义在共享框架 CarCore 中，桌面小组件的按钮也复用同一批 Intent；
/// - 每条指令能否被执行，还受 App 内「设置 → 语音命令」开关控制
///   （与网页版「专属密钥、只控制你自己的车」的安全策略一致）。
///
/// 协议要求（见 AppIntents.AppShortcutsProvider）：
///   @AppShortcutsBuilder static var appShortcuts: [AppShortcut] { get }
/// 必须是 static，且属性体走 @AppShortcutsBuilder 结果生成器风格
/// （多个 AppShortcut 表达式直接换行排列，无需数组括号与逗号）。
struct CarAppShortcuts: AppShortcutsProvider {

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UnlockCarIntent(),
            phrases: [
                "用\(.applicationName)解锁车辆",
                "解锁\(.applicationName)绑定的汽车"
            ],
            shortTitle: "解锁车辆",
            systemImageName: "lock.open"
        )
        AppShortcut(
            intent: LockCarIntent(),
            phrases: [
                "用\(.applicationName)锁上车",
                "锁定\(.applicationName)绑定的汽车"
            ],
            shortTitle: "锁定车辆",
            systemImageName: "lock"
        )
        AppShortcut(
            intent: FlashLightsIntent(),
            phrases: [
                "用\(.applicationName)闪灯",
                "让\(.applicationName)闪一下灯"
            ],
            shortTitle: "闪灯寻车",
            systemImageName: "light.beacon.max"
        )
        AppShortcut(
            intent: HonkHornIntent(),
            phrases: [
                "用\(.applicationName)鸣笛",
                "让\(.applicationName)响一下"
            ],
            shortTitle: "鸣笛寻车",
            systemImageName: "speaker.wave.2"
        )
        AppShortcut(
            intent: FindCarIntent(),
            phrases: [
                "用\(.applicationName)找车",
                "\(.applicationName)我的车停在哪"
            ],
            shortTitle: "寻车",
            systemImageName: "car.circle"
        )
        AppShortcut(
            intent: CarStatusIntent(),
            phrases: [
                "用\(.applicationName)查看车况",
                "\(.applicationName)车况怎么样"
            ],
            shortTitle: "查看车况",
            systemImageName: "gauge"
        )
        // 注意：Apple 限制每个 App 最多注册 10 个 App Shortcut，
        // 因此这里精选了 10 条最常用的语音短语（共 11 个 Intent）。
        // 「关闭车窗」Intent 仍存在于 CarCore，可通过快捷指令 App 与
        // 桌面小组件按钮使用，只是不注册 Siri 语音短语。
        AppShortcut(
            intent: StartEngineIntent(),
            phrases: ["用\(.applicationName)启动车辆"],
            shortTitle: "远程点火",
            systemImageName: "flame"
        )
        AppShortcut(
            intent: StopEngineIntent(),
            phrases: ["用\(.applicationName)熄灭发动机"],
            shortTitle: "远程熄火",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: OpenACIntent(),
            phrases: ["用\(.applicationName)打开空调"],
            shortTitle: "打开空调",
            systemImageName: "snowflake"
        )
        AppShortcut(
            intent: CloseACIntent(),
            phrases: ["用\(.applicationName)关闭空调"],
            shortTitle: "关闭空调",
            systemImageName: "snowflake.slash"
        )
    }
}
