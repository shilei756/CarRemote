import AppIntents
import CarCore

/// Siri 语音短语（"嘿 Siri，用 CAKOCHE 解锁车辆"）。
///
/// 语音体系分两层，互不影响：
/// - **App Shortcut（本文件，最多 10 条）**：注册即生效，不用手动添加，
///   负责「一句话就能用」的高频操作；
/// - **App Intent（CarControlIntents / CarQueryIntents / CarPageIntent）**：
///   全部 25 个动作，在「快捷指令」App 里按名称搜索即可拖进自动化，
///   数量不受限制，可单独命名、单独上锁屏、单独串进个人自动化。
///
/// 总开关在 App「设置 → Siri 语音控制」，关闭后所有语音指令立即失效。
@available(iOS 16.0, *)
struct CarAppShortcuts: AppShortcutsProvider {

    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        // 统一入口：说完后 Siri 追问「想对车做什么？」，覆盖全部 15 条指令
        AppShortcut(
            intent: ControlCarIntent(),
            phrases: [
                "用\(.applicationName)控制车辆",
                "用\(.applicationName)控制我的车"
            ],
            shortTitle: "控制车辆",
            systemImageName: "car.fill"
        )
        // 离车一步到位：闭锁 + 关窗（网页版 doLockAll 同款组合指令）
        AppShortcut(
            intent: OneKeyLockIntent(),
            phrases: [
                "用\(.applicationName)一键锁车",
                "用\(.applicationName)锁车关窗"
            ],
            shortTitle: "一键闭锁",
            systemImageName: "lock.circle.fill"
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
        AppShortcut(
            intent: CloseWindowsIntent(),
            phrases: ["用\(.applicationName)关上车窗"],
            shortTitle: "关闭车窗",
            systemImageName: "arrow.down.to.line"
        )
        // ↑ 共 10 条 —— Apple 限制每个 App 最多 10 个 App Shortcut。
        // 其余动作（闪灯 / 鸣笛 / 降窗 / 留缝 / 关天窗 / 天窗上翘 / 点火 / 熄火 /
        // 空调定温 / 续航油量 / 胎压 / 门窗状态 / 车内温度 / 账号授权 / 打开页面）
        // 全部在「快捷指令」App 里可搜索到，只是没有预置语音短语。
    }
}
