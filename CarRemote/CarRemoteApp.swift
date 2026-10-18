import SwiftUI
import UIKit
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
        // 体验到期 / 授权被撤销：不可关闭浮层，只留「退出登录」
        .fullScreenCover(isPresented: Binding(
            get: { appState.accessBlock != nil },
            set: { if !$0 { appState.accessBlock = nil } }
        )) {
            AccessBlockedModal(
                block: appState.accessBlock ?? AppState.AccessBlock(title: "", message: ""),
                onExit: { appState.forceLogout(message: appState.accessBlock?.message ?? "") }
            )
        }
    }
}

/// 权限失效浮层（对齐网页版 revokedMask：禁下滑关闭、禁长按菜单）
struct AccessBlockedModal: View {
    let block: AppState.AccessBlock
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(WebTheme.red)
                Text(block.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WebTheme.txt)
                Text(block.message)
                    .font(.system(size: 13))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(WebTheme.muted)
                    .padding(.horizontal, 8)
                Button {
                    onExit()
                } label: {
                    Text("退出登录")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(WebTheme.red)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(WebTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(WebTheme.border, lineWidth: 1)
            )
        }
        .interactiveDismissDisabled()
        .onAppear { UIAccessibility.post(notification: .screenChanged, argument: nil) }
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
