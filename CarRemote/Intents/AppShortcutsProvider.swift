import AppIntents
import CarCore

/// Siri 语音短语（"Hey Siri，用长安控车解锁车辆"）。
///
/// 重新设计后的语音体系：
/// - 「控制车辆」统一入口：Siri 追问要控制什么，一条指令覆盖全部控车能力，
///   高危操作（开锁/闭锁/点火/熄火）执行前会语音确认；
/// - 常用操作保留直达短语，说完即执行；
/// - 总开关在 App「设置 → Siri 语音控制」，关闭后所有语音指令立即失效。
///
/// 注意：Apple 限制每个 App 最多注册 10 个 App Shortcut。
@available(iOS 16.0, *)
struct CarAppShortcuts: AppShortcutsProvider {

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        // 统一入口：说完后 Siri 追问「想对车做什么？」，支持全部 14 条指令
        AppShortcut(
            intent: ControlCarIntent(),
            phrases: [
                "用\(.applicationName)控制车辆",
                "用\(.applicationName)控制我的车"
            ],
            shortTitle: "控制车辆",
            systemImageName: "car.fill"
        )
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
        // 1.9.0：删掉单独的「闪灯 / 鸣笛」两条直达短语（「寻车」本身就是闪灯+鸣笛），
        // 腾出 Apple 规定的 10 个名额给「查询车辆位置」与「车辆状态」。
        // 单独的闪灯 / 鸣笛仍可在「快捷指令」App 里搜索到对应动作手动运行。
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
                "用\(.applicationName)查看车辆状态",
                "\(.applicationName)车况怎么样",
                "用\(.applicationName)看看车门锁了没"
            ],
            shortTitle: "车辆状态",
            systemImageName: "gauge"
        )
        AppShortcut(
            intent: CarLocationIntent(),
            phrases: [
                "用\(.applicationName)查询车辆位置",
                "\(.applicationName)我的车在哪",
                "用\(.applicationName)找一下车停在哪"
            ],
            shortTitle: "车辆位置",
            systemImageName: "mappin.and.ellipse"
        )
        AppShortcut(
            intent: CloseWindowsIntent(),
            phrases: ["用\(.applicationName)关上车窗"],
            shortTitle: "关闭车窗",
            systemImageName: "arrow.down.to.line"
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
