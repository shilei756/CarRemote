import SwiftUI
import CarCore
import UserNotifications

@main
struct CarRemoteApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var themeManager = ThemeManager.shared

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
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    Task { await appState.handleForeground() }
                }
                // 系统偶尔会重置 window.bounds（旋转 / 状态栏变化 / 键盘弹出），
                // 每次激活重新套用缩放，避免界面变形或底部标签栏错位。
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    DispatchQueue.main.async {
                        applyUIScale(CGFloat(SharedStore.loadSettings().uiScale))
                    }
                }
        }
    }
}

/// 根视图：根据登录/授权状态切换界面
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    // 主题观察：主题变化时整棵视图树重算，WebTheme 静态色值随之刷新
    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var announcementCenter = AnnouncementCenter()

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
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.phase)
        .onAppear { applyUIScale(CGFloat(SharedStore.loadSettings().uiScale)) }
        // 启动后拉一次站主后台公告；失败静默，仅在有新公告时弹一次
        .task {
            if appState.phase == .ready {
                await announcementCenter.check()
            }
        }
        // 异步恢复登录时会从 .loading 跳到 .ready，补一次公告拉取
        .onChange(of: appState.phase) { phase in
            if phase == .ready {
                Task { await announcementCenter.check() }
            }
        }
        .sheet(item: $announcementCenter.current) { notice in
            AnnouncementSheet(notice: notice) {
                announcementCenter.dismiss(notice)
            }
        }
        // 点击「车辆异常」通知直接回到控车页
        .onReceive(NotificationCenter.default.publisher(for: .vehicleAlertTapped)) { _ in
            TabRouter.shared.select(.control)
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
