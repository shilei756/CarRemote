import SwiftUI
import CarCore

@main
struct CarRemoteApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var themeManager = ThemeManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(themeManager)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    Task { await appState.handleForeground() }
                }
        }
    }
}

/// 根视图：根据登录/授权状态切换界面
struct RootView: View {
    @EnvironmentObject private var appState: AppState
    // 主题观察：主题变化时整棵视图树重算，WebTheme 静态色值随之刷新
    @EnvironmentObject private var themeManager: ThemeManager

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
