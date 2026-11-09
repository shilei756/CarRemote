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
    /// 空调开通剩余天数（nil = 未开通或查询失败，界面隐藏）
    @Published var acRemainingDays: Int?
    /// 开空调调温弹窗（新版链路，网页版 openAcTempModal）
    @Published var showACTempModal = false
    /// 防误触确认待执行的开空调目标温度（调温弹窗确认后仍需二次确认时携带）
    @Published var pendingTemp: Int?

    // 更多功能面板
    @Published var showHistoryActions = false
    @Published var showMessages = false
    @Published var showTrips = false
    @Published var showEmbed: EmbedTarget?   // "vehicle_status" / "panorama"
    @Published var showWhitelist = false
    /// 车辆位置详情弹窗（点击位置入口才查询并弹出）
    @Published var showLocationDetail = false

    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        acMode = SharedStore.loadACMode()
    }

    var settings: AppSettings {
        SharedStore.loadSettings()
    }

    // MARK: - 指令执行

    /// 点击控车按钮：新版链路开空调先弹调温窗（网页版 openAcTempModal），
    /// 高危操作先弹防误触确认。
    /// 1.10.0：取消闭锁方式选择层——「闭锁」直接下发普通锁车，
    ///「一键闭锁」作为快捷栏独立按钮直接下发组合指令（LockDoor → 4.5s → CloseWindow）。
    func execute(_ command: CarCommand) {
        if command == .openAir, acMode == .new {
            showACTempModal = true
            return
        }
        if settings.needsConfirm(command: command) {
            pendingConfirm = command
            return
        }
        run(command)
    }

    func confirmPending() {
        guard let command = pendingConfirm else { return }
        pendingConfirm = nil
        let temp = pendingTemp
        pendingTemp = nil
        run(command, temperature: temp)
    }

    func cancelPending() {
        pendingConfirm = nil
        pendingTemp = nil
    }

    /// 调温弹窗默认温度（网页版优先级）：上次使用 > 车机当前设定 > 24
    func defaultACTemp(currentCarTemp: Double?) -> Int {
        if let saved = SharedStore.loadACLastTemp() { return saved }
        if let currentCarTemp, currentCarTemp >= 10, currentCarTemp <= 40 {
            return Int(currentCarTemp.rounded())
        }
        return 24
    }

    /// 调温弹窗「开启空调」：记住温度 →（开了防误触则先确认）→ 随指令下发
    func confirmACTemp(_ temp: Int) {
        SharedStore.saveACLastTemp(temp)
        if settings.needsConfirm(command: .openAir) {
            pendingConfirm = .openAir
            pendingTemp = temp
            return
        }
        run(.openAir, temperature: temp)
    }

    private func run(_ command: CarCommand, temperature: Int? = nil) {
        guard let appState, let credentials = appState.credentials else { return }
        executingCommand = command
        Task {
            defer { executingCommand = nil }
            do {
                let result: CommandResult
                if (command == .openAir || command == .closeAir), acMode == .new {
                    // 空调新版链路（网页版 newAC：开放平台，需已扫码开通）
                    result = try await ACService.executeOfficial(command: command, credentials: credentials, temperature: temperature)
                } else {
                    // 其余指令与空调官方版（网页版 performAction：直连长安链路）
                    result = try await CarService.execute(command: command, credentials: credentials)
                }
                toast = toastText(command: command, result: result, temperature: temperature)
                WidgetCenter.shared.reloadAllTimelines()
                if result.ok {
                    await appState.refreshStatus()
                }
            } catch {
                var message = error.localizedDescription
                if (command == .openAir || command == .closeAir), acMode == .new,
                   message.contains("开通") || message.contains("凭证") {
                    message += "，点击「更多功能 → 空调开通」扫码授权"
                }
                toast = "❌ \(command.displayName)失败：\(message)"
            }
        }
    }

    private func toastText(command: CarCommand, result: CommandResult, temperature: Int? = nil) -> String {
        if result.ok {
            // 一键闭锁是两条指令的组合，直接展示合并后的执行结果
            if command == .oneKeyLock { return "✅ \(result.message)" }
            if command == .openAir, let temperature {
                return "✅ 开空调指令已发送（目标 \(temperature)°C）"
            }
            return "✅ \(command.displayName)指令已发送"
        }
        if command == .oneKeyLock { return "❌ \(result.message)" }
        return "❌ \(command.displayName)失败：\(result.message)"
    }

    // MARK: - 空调模式

    func setACMode(_ mode: ACMode) {
        acMode = mode
        SharedStore.saveACMode(mode)
        if mode == .new {
            // 切到新版时刷新一次开通剩余天数
            Task { await loadACRemainingDays() }
        }
    }

    /// 查询空调开通剩余天数（新版链路专用）
    func loadACRemainingDays() async {
        guard let appState, let credentials = appState.credentials else { return }
        acRemainingDays = await ACService.activationRemainingDays(credentials: credentials)
    }

    // MARK: - 查询车况（对齐网页版 sendQueryStatus：唤醒车机上报最新数据）

    /// 「查询车况」不是简单刷新已缓存的车辆信息，而是下发 UpCarCondition
    /// 唤醒车机重新上报，随后主动读取车辆位置与最新车况（网页版
    /// sendQueryStatus → autoRefreshAfterCmd + loadLocationCard 的等价实现）。
    /// 返回 (是否成功, 反馈文案)，由界面即时展示。
    func queryVehicleCondition() async -> (ok: Bool, message: String) {
        guard let appState, let credentials = appState.credentials else {
            return (false, "未登录，请先登录后再查询")
        }
        do {
            // PIN 校验 → 安全公钥 → 站内加密代理 → execute，链路与网页版完全一致
            let result = try await CarService.performAction(
                action: "UpCarCondition", credentials: credentials
            )
            guard result.ok else {
                return (false, result.message)
            }
            // 唤醒已送达：立即读取一次最新车辆位置，并弹出详情把读回的
            // 地址 / 定位时间 / 经纬度 / 车速直接呈现给「查询车况」的用户
            loadLocation()
            showLocationDetail = true
            // 车机上报存在延迟，按网页版 2 / 8 / 15 秒节奏补刷车况与位置
            Task { [weak self] in
                for delay: UInt64 in [2, 6, 7] {
                    try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
                    await self?.appState?.refreshStatus()
                    self?.loadLocation()
                }
            }
            return (true, "车况查询已发送，车辆位置与状态即将更新")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: - 车辆位置

    /// 点击位置入口：查询一次并弹出详情（对齐网页版「点定位 → 弹详情」）
    func queryLocation() {
        loadLocation()
        showLocationDetail = true
    }

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

    /// 自定义布局弹窗
    @Published var showLayoutEditor = false

    /// 保存自定义布局（控车按钮顺序 + 更多功能磁贴顺序 + 隐藏项），并立即刷新小组件
    func saveLayout(quick: [CarCommand], more: [CarCommand], tools: [MoreTool],
                    hiddenQuick: Set<String>, hiddenMore: Set<String>, hiddenTools: Set<String>) {
        var settings = SharedStore.loadSettings()
        settings.quickCommands = quick.map { $0.rawValue }
        settings.moreCommands = more.map { $0.rawValue }
        settings.moreTools = tools.map { $0.rawValue }
        settings.hiddenQuickCommands = hiddenQuick
        settings.hiddenMoreCommands = hiddenMore
        settings.hiddenTools = hiddenTools
        SharedStore.saveSettings(settings)
        // 布局随车况快照一起共享（重签环境下独立通道可能失效）
        if let status = appState?.status {
            SharedStore.saveStatusSnapshot(StatusSnapshot(
                carName: appState?.carName ?? "我的爱车",
                status: status,
                widgetCommands: settings.widgetCommands
            ))
        }
        WidgetCenter.shared.reloadAllTimelines()
        objectWillChange.send()
    }

    /// 恢复默认布局（同时清除所有隐藏项，回到出厂全部可见）
    func resetLayout() {
        var settings = SharedStore.loadSettings()
        settings.quickCommands = CarCommand.primaryCommands.map { $0.rawValue }
        settings.moreCommands = CarCommand.extraCommands.map { $0.rawValue }
        settings.moreTools = MoreTool.defaultOrder.map { $0.rawValue }
        settings.showAllFeatures()
        SharedStore.saveSettings(settings)
        objectWillChange.send()
    }

    // MARK: - 导航到车（优先拉起高德 App，未安装回退网页版）

    func navigateToCar() {
        guard let status = appState?.status, let location = status.location else { return }
        let name = locationInfo?.address ?? "车辆位置"
        let lat = location.latitude
        let lon = location.longitude
        // 高德 App 导航 Scheme（iosamap://）：直接拉起 App 内导航，而非打开网页
        let appRaw = "iosamap://navi?sourceApplication=\(bundleName)&backScheme=carremote&lat=\(lat)&lon=\(lon)&dev=0&style=2"
        let appString = appRaw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? appRaw
        if let appURL = URL(string: appString) {
            UIApplication.shared.open(appURL, options: [:]) { opened in
                // 高德未安装或拉起失败 → 回退网页版高德导航
                guard !opened else { return }
                let webRaw = "https://uri.amap.com/navigation?to=\(lon),\(lat),\(name)&mode=car&coordinate=gaode&callnative=1"
                if let webURL = URL(string: webRaw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? webRaw) {
                    UIApplication.shared.open(webURL)
                }
            }
            return
        }
        // 极端兜底：直接走网页版
        let webRaw = "https://uri.amap.com/navigation?to=\(lon),\(lat),\(name)&mode=car&coordinate=gaode&callnative=1"
        if let webURL = URL(string: webRaw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? webRaw) {
            UIApplication.shared.open(webURL)
        }
    }

    private var bundleName: String {
        Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleName"] as? String
            ?? "长安控车"
    }
}

/// 内嵌网页目标（车辆状态 / 360全景）
struct EmbedTarget: Identifiable, Equatable {
    let id: String
    var key: String { id }

    static let vehicleStatus = EmbedTarget(id: "vehicle_status")
    static let panorama = EmbedTarget(id: "panorama")
}

/// 底部 Tab 路由（更多功能磁贴跨页跳转用）
@MainActor
final class TabRouter: ObservableObject {
    static let shared = TabRouter()

    enum Tab: Int, CaseIterable {
        case control = 0
        case status = 1
        case fuel = 2
        case maintenance = 3
        case profile = 4
    }

    @Published var selectedTab: Tab = .control

    func select(_ tab: Tab) {
        selectedTab = tab
    }
}
