import SwiftUI
import CarCore
import WidgetKit

/// 全局状态机：登录 → 卡密体验网关 → 主界面。
/// 白名单/封禁/卡密的判定逻辑与网页版保持一致。
@MainActor
final class AppState: ObservableObject {

    enum Phase: Equatable {
        case loading
        case loggedOut
        case needsCard
        case ready
    }

    @Published var phase: Phase = .loading
    @Published var credentials: Credentials?
    @Published var cardStatus: CardService.CardStatus?
    /// 左上角展示名：DIY 名优先，其次官网车名
    @Published var carName: String = APIConfig.defaultCarName
    /// 用户 DIY 车辆名称（左上角长方形可点击编辑；空串 = 跟随官网原名）
    @Published var customCarName: String = SharedStore.loadCustomCarName() {
        didSet {
            guard customCarName != oldValue else { return }
            SharedStore.saveCustomCarName(customCarName)
            applyCarName()
        }
    }
    @Published var status: CarStatus?
    @Published var statusUpdatedAt: Date?
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    /// 当前账号是否有管理入口（网页版 applyAdminEntry：/admin/is_admin）
    @Published var isAdminUser = false
    /// 当前神兽主题（网页版 localStorage myth_theme；变化时整树重算配色）
    @Published var mythTheme: MythTheme? {
        didSet { SharedStore.saveMythTheme(mythTheme) }
    }
    /// 权限被吊销 / 体验到期时弹出的不可关闭浮层（对齐网页版 revokedMask）
    @Published var accessBlock: AccessBlock?
    /// 不可关闭浮层的数据
    struct AccessBlock: Equatable {
        var title: String
        var message: String
    }

    private var foregroundBeated = false

    init() {
        restore()
        mythTheme = SharedStore.loadMythTheme()
        applyCarName()
    }

    /// carName = DIY 名（非空）→ 官网原名 → 默认名
    private func applyCarName() {
        let custom = customCarName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty {
            carName = custom
        } else if let snapshotName = SharedStore.loadStatusSnapshot()?.carName, !snapshotName.isEmpty {
            carName = snapshotName
        } else {
            carName = APIConfig.defaultCarName
        }
    }

    // MARK: - 会话恢复

    private func restore() {
        guard let credentials = SharedStore.loadCredentials() else {
            phase = .loggedOut
            return
        }
        self.credentials = credentials
        // 关键：从 Keychain 恢复会话时必须回写 App Group 兜底副本。
        // 覆盖安装场景下 Keychain 保留旧凭据、defaults 里没有（从没重新登录过），
        // 小组件进程读不到凭据会一直显示「未登录」。
        SharedStore.saveCredentials(credentials)
        Task { await verifyAccess(credentials) }
    }

    /// 登录后 / 恢复会话后校验授权（白名单 + 卡密）
    private func verifyAccess(_ credentials: Credentials) async {
        phase = .loading
        do {
            let status = try await CardService.status(phone: credentials.phone)
            cardStatus = status
            phase = status.authorized ? .ready : .needsCard
        } catch {
            // 权限接口异常不阻塞正常用户（服务端仍会二次校验关键操作）
            phase = .ready
        }
        if phase == .ready {
            await reportUsage()
            await refreshAdminRole()
            await refreshStatus()
            startAccessMonitor()
        }
    }

    /// 探测当前账号是否为管理员（决定白名单管理入口显隐）
    func refreshAdminRole() async {
        guard let credentials else {
            isAdminUser = false
            return
        }
        isAdminUser = await AdminService.isAdmin(phone: credentials.phone)
    }

    // MARK: - 登录 / 登出

    func loginCompleted(_ credentials: Credentials) {
        SharedStore.saveCredentials(credentials)
        self.credentials = credentials
        foregroundBeated = false
        Task { await verifyAccess(credentials) }
    }

    func cardVerified() {
        guard let credentials else { return }
        Task { await verifyAccess(credentials) }
    }

    func logout() {
        SharedStore.saveCredentials(nil)
        SharedStore.clearStatusSnapshot()
        credentials = nil
        cardStatus = nil
        status = nil
        statusUpdatedAt = nil
        isAdminUser = false
        accessBlock = nil
        stopAccessMonitor()
        phase = .loggedOut
    }

    /// 强制退出（体验到期 / 被移出白名单）：清凭据并提示，不保留会话
    func forceLogout(message: String) {
        accessBlock = nil
        logout()
        errorMessage = message
    }

    // MARK: - 权限复查（对齐网页版：每 60 秒 + 回前台各查一次）

    private var accessTimer: Timer?

    func startAccessMonitor() {
        stopAccessMonitor()
        accessTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { await self?.recheckAccess() }
        }
    }

    func stopAccessMonitor() {
        accessTimer?.invalidate()
        accessTimer = nil
    }

    /// 复查账号权限。发现无权使用时盖上不可关闭浮层，只留「退出登录」。
    func recheckAccess() async {
        guard phase == .ready, let credentials else { return }
        // 卡密到期（体验用户 24 小时）
        if let status = try? await CardService.status(phone: credentials.phone) {
            if !status.authorized {
                accessBlock = AccessBlock(
                    title: "体验权限已到期",
                    message: status.message ?? "体验卡自激活起 24 小时有效，已到期。请重新输入卡密或联系站主开通。"
                )
                stopAccessMonitor()
                return
            }
        }
        // 被移出白名单 / 被拉黑
        if let ok = await CardService.authStatus(phone: credentials.phone, pin: credentials.pin), ok == false {
            accessBlock = AccessBlock(title: "账号已无法继续使用", message: "当前账号的授权已被撤销，请重新登录或联系站主。")
            stopAccessMonitor()
        }
    }
    // MARK: - 前台 / 用量上报

    func handleForeground() async {
        guard phase == .ready else { return }
        if !foregroundBeated {
            foregroundBeated = true
            await reportUsage()
        }
        await refreshStatus()
        await recheckAccess()
    }

    private func reportUsage() async {
        guard let credentials else { return }
        await UsageService.beat(phone: credentials.phone)
    }

    // MARK: - 车况刷新

    func refreshStatus() async {
        guard let credentials, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let (status, car, updatedCredentials) = try await CarService.refresh(credentials: credentials)
            SharedStore.saveCredentials(updatedCredentials)
            self.status = status
            self.statusUpdatedAt = Date()
            SharedStore.saveStatusSnapshot(StatusSnapshot(
                carName: car.displayName,
                status: status,
                // 按钮配置随快照共享（重签环境下独立通道可能失效）
                widgetCommands: SharedStore.loadSettings().widgetCommands
            ))
            applyCarName()
            errorMessage = nil
            // 车况快照已更新，立即刷新桌面小组件
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // 任务被系统取消（切标签页/重复下拉/轮询重启）不视为网络故障，静默忽略
            if Task.isCancelled { return }
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            errorMessage = error.localizedDescription
        }
    }
}
