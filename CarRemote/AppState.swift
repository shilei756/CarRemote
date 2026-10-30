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

        // 秒开：已有车况快照时，先用上次数据把控车页渲染出来，
        // 授权校验与车况刷新全部在后台异步跑，不再阻塞首屏。
        if let snapshot = SharedStore.loadStatusSnapshot() {
            self.status = CarStatus(snapshot: snapshot)
            self.statusUpdatedAt = snapshot.updatedAt
            applyCarName()
            // 立刻进入主界面（首屏构建即可见，无需等待网络）
            phase = .ready
            // 后台校验授权；若已失效会在回调里踢回登录 / 卡密网关
            Task { await verifyAccess(credentials, restoredSession: true, showLoading: false) }
        } else {
            // 无快照（极少见，如快照被清）：走原有「先校验再进」流程，避免空壳闪烁
            Task { await verifyAccess(credentials, restoredSession: true) }
        }
    }

    /// 登录后 / 恢复会话后校验授权（白名单 + 卡密）。
    /// restoredSession = 再次打开 App 时的会话恢复：此时权限失效直接踢出登录态
    ///（清凭据回登录页）；刚登录 / 刚验证卡密的场景仍走卡密网关，避免反复踢出。
    /// showLoading = 是否在等待期间展示启动占位（校验网络）；秒开场景传 false，
    /// 因为界面已用快照先行渲染，无需再回退到加载态。
    private func verifyAccess(_ credentials: Credentials, restoredSession: Bool = false, showLoading: Bool = true) async {
        if showLoading { phase = .loading }
        do {
            let status = try await CardService.status(phone: credentials.phone)
            cardStatus = status
            if !status.authorized, restoredSession {
                forceLogout(message: "登录已失效：体验权限已到期或授权已被撤销，请重新登录。")
                return
            }
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
        errorMessage = nil
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
        errorMessage = nil
        stopAccessMonitor()
        phase = .loggedOut
    }

    /// 强制退出（体验到期 / 被移出白名单，含使用中到期）：清凭据并提示，不保留会话
    func forceLogout(message: String) {
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

    /// 复查账号权限。发现无权使用时直接踢出登录态（使用中到期也踢）：
    /// 清凭据回登录页，并在登录页横幅展示原因（对齐网页版 revokedMask 的严格程度）。
    func recheckAccess() async {
        guard phase == .ready, let credentials else { return }
        // 卡密到期（体验用户 24 小时）
        if let status = try? await CardService.status(phone: credentials.phone), !status.authorized {
            forceLogout(message: "体验权限已到期：\(status.message ?? "体验卡自激活起 24 小时有效，请重新输入卡密或联系站主开通。")")
            return
        }
        // 被移出白名单 / 被拉黑
        if let ok = await CardService.authStatus(phone: credentials.phone, pin: credentials.pin), ok == false {
            forceLogout(message: "账号已无法继续使用：当前账号的授权已被撤销，请重新登录或联系站主。")
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
