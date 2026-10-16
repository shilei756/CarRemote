import SwiftUI
import CarCore
import UIKit
import WidgetKit

/// 仪表盘视图模型：车况刷新 + 控车指令执行（含防误触二次确认）
@MainActor
final class DashboardViewModel: ObservableObject {

    @Published var executingCommand: CarCommand?
    @Published var pendingConfirm: CarCommand?
    @Published var toast: String?
    @Published var showMoreControls = false

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    var settings: AppSettings {
        SharedStore.loadSettings()
    }

    // MARK: - 指令执行

    /// 点击控车按钮：高危操作先弹防误触确认
    func execute(_ command: CarCommand) {
        if settings.needsConfirm(command: command) {
            pendingConfirm = command
            return
        }
        run(command)
    }

    func confirmPending() {
        guard let command = pendingConfirm else { return }
        pendingConfirm = nil
        run(command)
    }

    func cancelPending() {
        pendingConfirm = nil
    }

    private func run(_ command: CarCommand) {
        guard let appState, let credentials = appState.credentials else { return }
        executingCommand = command
        Task {
            defer { executingCommand = nil }
            do {
                let result = try await CarService.execute(command: command, credentials: credentials)
                toast = toastText(command: command, result: result)
                WidgetCenter.shared.reloadAllTimelines()
                if result.ok {
                    await appState.refreshStatus()
                }
            } catch {
                toast = "❌ \(command.displayName)失败：\(error.localizedDescription)"
            }
        }
    }

    private func toastText(command: CarCommand, result: CommandResult) -> String {
        if result.ok {
            return "✅ \(command.displayName)指令已发送"
        }
        return "❌ \(command.displayName)失败：\(result.message)"
    }

    // MARK: - 设置联动

    func toggleConfirm(command: CarCommand) {
        var settings = SharedStore.loadSettings()
        settings.toggleConfirm(command: command)
        SharedStore.saveSettings(settings)
        objectWillChange.send()
    }

    // MARK: - 导航到车

    func navigateToCar() {
        guard let status = appState?.status, let location = status.location else { return }
        let urlString = "https://maps.apple.com/?daddr=\(location.latitude),\(location.longitude)&dirflg=d"
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}
