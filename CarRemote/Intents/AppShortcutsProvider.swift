import AppIntents

/// Siri 语音短语（"Hey Siri，用远程控车解锁车辆"）。
///
/// 说明：
/// - Intent 定义在共享框架 CarCore 中，桌面小组件的按钮也复用同一批 Intent；
/// - 每条指令能否被执行，还受 App 内「设置 → 语音命令」开关控制
///   （与网页版「专属密钥、只控制你自己的车」的安全策略一致）。
struct CarAppShortcuts: AppShortcutsProvider {

    var appShortcuts: [AppShortcut] {
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
        AppShortcut(
            intent: CloseWindowsIntent(),
            phrases: ["用\(.applicationName)关车窗"],
            shortTitle: "关闭车窗",
            systemImageName: "wind.slash"
        )
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
