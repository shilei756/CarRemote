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
            RootView()
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
        }
    }
}

/// 根视图：根据登录/授权状态切换界面
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    // 主题观察：主题变化时整棵视图树重算，WebTheme 静态色值随之刷新
    @EnvironmentObject private var themeManager: ThemeManager
    // 1.6.0 公告中心：只在进入主界面后呈现弹窗，登录 / 卡密网关阶段不打扰
    @EnvironmentObject private var announcementCenter: AnnouncementCenter
    // 1.9.0 #3：跟随手机白夜模式
    @Environment(\.colorScheme) private var colorScheme

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
            // 首次进入同步一次系统深浅（冷启动时系统可能已是浅色）
            themeManager.syncSystem(isDark: colorScheme == .dark)
            VehicleAlertService.clearAppBadge()
        }
        // 控制中心 / 设置里切换深浅、或系统按时自动切换时立即同步
        .onChange(of: colorScheme) { newValue in
            themeManager.syncSystem(isDark: newValue == .dark)
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
