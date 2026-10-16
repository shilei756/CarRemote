import SwiftUI
import CarCore

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
    @Published var carName: String = APIConfig.defaultCarName
    @Published var status: CarStatus?
    @Published var statusUpdatedAt: Date?
    @Published var isRefreshing = false
    @Published var errorMessage: String?

    private var foregroundBeated = false

    init() {
        restore()
    }

    // MARK: - 会话恢复

    private func restore() {
        guard let credentials = SharedStore.loadCredentials() else {
            phase = .loggedOut
            return
        }
        self.credentials = credentials
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
            await refreshStatus()
        }
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
            self.carName = car.displayName
            self.statusUpdatedAt = Date()
            SharedStore.saveStatusSnapshot(StatusSnapshot(carName: car.displayName, status: status))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
