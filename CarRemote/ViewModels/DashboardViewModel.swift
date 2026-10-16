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

    // 位置
    @Published var locationInfo: CarLocationInfo?
    @Published var isLoadingLocation = false

    // 空调
    @Published var acMode: ACMode
    @Published var showACQR = false

    // 更多功能面板
    @Published var showHistoryActions = false
    @Published var showMessages = false
    @Published var showTrips = false
    @Published var showEmbed: String?   // "vehicle_status" / "panorama"
    @Published var showWhitelist = false

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        acMode = SharedStore.loadACMode()
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
                let result: CommandResult
                if (command == .openAir || command == .closeAir), acMode == .official {
                    // 空调官方正版链路（需已扫码开通）
                    result = try await ACService.executeOfficial(command: command, credentials: credentials)
                } else {
                    result = try await CarService.execute(command: command, credentials: credentials)
                }
                toast = toastText(command: command, result: result)
                WidgetCenter.shared.reloadAllTimelines()
                if result.ok {
                    await appState.refreshStatus()
                }
            } catch {
                var message = error.localizedDescription
                if (command == .openAir || command == .closeAir), acMode == .official,
                   message.contains("开通") || message.contains("凭证") {
                    message += "，点击「更多功能 → 空调开通」扫码授权"
                }
                toast = "❌ \(command.displayName)失败：\(message)"
            }
        }
    }

    private func toastText(command: CarCommand, result: CommandResult) -> String {
        if result.ok {
            return "✅ \(command.displayName)指令已发送"
        }
        return "❌ \(command.displayName)失败：\(result.message)"
    }

    // MARK: - 空调模式

    func setACMode(_ mode: ACMode) {
        acMode = mode
        SharedStore.saveACMode(mode)
    }

    // MARK: - 车辆位置

    func loadLocation() {
        guard let appState, let credentials = appState.credentials else { return }
        isLoadingLocation = true
        Task {
            defer { isLoadingLocation = false }
            do {
                let (token, updated) = try await AuthService.validAccessToken(for: credentials)
                SharedStore.saveCredentials(updated)
                let cars = try await CarService.fetchCars(accessToken: token)
                guard let car = cars.first else { return }
                locationInfo = try await CarService.fetchLocation(carId: car.carId, accessToken: token)
            } catch {
                // 位置失败静默：保留经纬度兜底展示
            }
        }
    }

    // MARK: - 设置联动

    func toggleConfirm(command: CarCommand) {
        var settings = SharedStore.loadSettings()
        settings.toggleConfirm(command: command)
        SharedStore.saveSettings(settings)
        objectWillChange.send()
    }

    // MARK: - 导航到车（高德 URI，与网页版一致）

    func navigateToCar() {
        guard let status = appState?.status, let location = status.location else { return }
        let name = locationInfo?.address ?? "车辆位置"
        let urlString = "https://uri.amap.com/navigation?to=\(location.longitude),\(location.latitude),\(name)&mode=car&coordinate=gaode&callnative=1"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? urlString
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

/// 底部 Tab 路由（更多功能磁贴跨页跳转用）
@MainActor
final class TabRouter: ObservableObject {
    static let shared = TabRouter()

    enum Tab: Int, CaseIterable {
        case control = 0
        case club = 1
        case fuel = 2
        case maintenance = 3
        case profile = 4
    }

    @Published var selectedTab: Tab = .control

    func select(_ tab: Tab) {
        selectedTab = tab
    }
}
