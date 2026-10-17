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
        phase = .loggedOut
    }
    // MARK: - 前台 / 用量上报

    func handleForeground() async {
        guard phase == .ready, !foregroundBeated else { return }
        foregroundBeated = true
        await reportUsage()
        await refreshStatus()
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
            SharedStore.saveStatusSnapshot(StatusSnapshot(carName: car.displayName, status: status))
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
