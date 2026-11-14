import SwiftUI
import CarCore
import UserNotifications

@main
struct CarRemoteApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var themeManager = ThemeManager.shared
    // 1.6.0 站主公告：全局单例，沿视图树下发；普通用户只读到弹窗，读不到发布入口
    @StateObject private var announcementCenter = AnnouncementCenter()

    init() {
        // 本地通知代理：App 在前台时也让「车辆异常持续提醒」横幅可见，
        // 点击通知可一键回到控车页。仅为已授权用户生效，不在此处请求权限。
        UNUserNotificationCenter.current().delegate = VehicleAlertNotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
#if CAKOCHE
            // CAKOCHE：全新极简 UI + 强制网站白名单门禁，配色由 Mono 自行定义。
            // 强制浅色，避免系统语义色在手机深色模式下擅自变暗造成割裂。
            CakocheRootView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
#else
            AppearanceRoot()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .environmentObject(announcementCenter)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    // 1.9.0 #4：通知划掉后回前台立即清角标，桌面图标不再残留小红点
                    VehicleAlertService.clearAppBadge()
                    Task {
                        await appState.handleForeground()
                        // 站主刚发过公告时，用户切回前台就能看到（内部 20 秒节流）
                        await announcementCenter.check()
                    }
                }
                // 系统偶尔会重置 window.bounds（旋转 / 状态栏变化 / 键盘弹出），
                // 每次激活重新套用缩放，避免界面变形或底部标签栏错位。
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    DispatchQueue.main.async {
                        applyUIScale(CGFloat(SharedStore.loadSettings().uiScale))
                        VehicleAlertService.clearAppBadge()
                    }
                }
                // 1.9.0 #5：iOS 16 小组件按钮通过深链回 App 执行
                .onOpenURL { url in
                    appState.handleWidgetURL(url)
                }
                // 执行结果 / 绑定指引（与 RootView 内的确认弹窗分属不同视图层级）
                .alert("小组件控车", isPresented: Binding(
                    get: { appState.widgetCommandResult != nil },
                    set: { if !$0 { appState.widgetCommandResult = nil } }
                )) {
                    Button("好", role: .cancel) { appState.widgetCommandResult = nil }
                } message: {
                    Text(appState.widgetCommandResult ?? "")
                }
#endif
        }
    }
}

/// 外观根（1.10.0）：把「系统语义色」与「WebTheme 自定义色」钉到同一个 colorScheme。
///
/// 之前割裂的根因：TabBar / Form / `.secondary` 文字 / `Color(.systemBackground)`
/// 这些系统控件无条件跟随手机深浅，而 WebTheme 是读 UserDefaults 求值的静态快照色，
/// 还额外要求「App 内夜间开关已开」。于是手机深色、开关没开时，
/// 只有系统控件变黑、自定义白卡还是白的 —— 就是「只黑了贴片」。
///
/// 现在只有两态，不再猜测「系统真实深浅」（UIScreen 的 userInterfaceStyle 在 iOS 上
/// 常返回 unspecified，不可靠）：
///  - App 内夜间开关【开】且无神兽主题 → `nil`（不干预，完全跟随手机系统深浅）；
///  - 开关【关】或有神兽主题 → `.light`（强制浅色，压住系统控件的自动变黑）。
/// 自定义色同时改为 UIKit 动态色，跟随同一个 trait 自动重解析，
/// 于是系统控件与自定义卡片永远整体一起变深 / 一起变浅，不再割裂。
private struct AppearanceRoot: View {
    @EnvironmentObject private var themeManager: ThemeManager
    @EnvironmentObject private var appState: AppState

    private var preferredScheme: ColorScheme? {
        // 神兽主题有自己一整套配色，强制浅色以免系统控件擅自变黑
        if appState.mythTheme != nil { return .light }
        return themeManager.theme == .dark ? nil : .light
    }

    var body: some View {
        RootView()
            .preferredColorScheme(preferredScheme)
            // 主题 / 神兽主题切换时触发一次重绘，动态色随之重解析
            .animation(.easeInOut(duration: 0.2), value: preferredScheme)
    }
}

/// 根视图：根据登录/授权状态切换界面
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    // 1.6.0 公告中心：只在进入主界面后呈现弹窗，登录 / 卡密网关阶段不打扰
    @EnvironmentObject private var announcementCenter: AnnouncementCenter

    var body: some View {
        Group {
            switch appState.phase {
            case .loading:
                LaunchView()
            case .loggedOut:
                LoginView()
            case .needsCard:
                CardGateView()
            case .ready:
                MainTabView()
                    .onAppear { Task { await announcementCenter.check() } }
                    // 公告弹窗挂在主界面分支：所有已登录用户可见，且没有任何入口
                    .sheet(item: Binding(
                        get: { announcementCenter.pending },
                        set: { item in
                            // 下拉关闭也记为已读，避免回前台反复弹出
                            if item == nil, let id = announcementCenter.pending?.id {
                                announcementCenter.markRead(id)
                            }
                        }
                    )) { notice in
                        AnnouncementSheet(notice: notice) {
                            announcementCenter.markRead(notice.id)
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.phase)
        .onAppear {
            applyUIScale(CGFloat(SharedStore.loadSettings().uiScale))
            VehicleAlertService.clearAppBadge()
            #if !CAKOCHE
            applyPendingPage()
            #endif
        }
        // 「打开 App 页面」快捷指令会拉起 App 并写下待跳转标记，回前台时消费
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            #if !CAKOCHE
            applyPendingPage()
            #endif
        }
        // 点击「车辆异常」通知直接回到控车页
        .onReceive(NotificationCenter.default.publisher(for: .vehicleAlertTapped)) { _ in
            TabRouter.shared.select(.control)
        }
        // 1.9.0 #5：iOS 16 点按小组件按钮 → 深链回 App → 二次确认后执行
        .alert("小组件控车确认", isPresented: Binding(
            get: { appState.pendingWidgetCommand != nil },
            set: { if !$0 { appState.cancelWidgetCommand() } }
        )) {
            Button("取消", role: .cancel) { appState.cancelWidgetCommand() }
            Button("确认执行", role: .destructive) {
                Task { await appState.confirmWidgetCommand() }
            }
        } message: {
            Text("确认要执行「\(appState.pendingWidgetCommand?.displayName ?? "")」吗？")
        }
    }

    /// 消费「打开 App 页面」快捷指令写下的标记，映射到正式版 5 个 Tab。
    /// CAKOCHE 侧由 CakocheRoot.applyPendingPage() 消费同一标记（各自 root 互斥，不冲突）。
    /// 用字符串字面量比较，避免引用 @available(iOS 16) 的 AppEnum 类型。
    #if !CAKOCHE
    private func applyPendingPage() {
        guard let raw = CakochePendingPage.consume() else { return }
        switch raw {
        case "mine": TabRouter.shared.select(.profile)
        default: TabRouter.shared.select(.control)   // home / climate → 控车首页（空调在此页）
        }
    }
    #endif
}

/// 启动占位
struct LaunchView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "car.circle")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("长安控车")
                .font(.title.bold())
            ProgressView()
        }
    }
}
