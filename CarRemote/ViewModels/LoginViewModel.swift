import SwiftUI
import CarCore

/// 登录 / 注册视图模型
@MainActor
final class LoginViewModel: ObservableObject {

    enum Mode: String, CaseIterable {
        case password = "控车码登录"
        case sms = "短信注册"
    }

    @Published var mode: Mode = .password
    @Published var phone = ""
    @Published var pin = ""
    @Published var smsCode = ""
    @Published var isSubmitting = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published var cooldown = 0

    private var cooldownTask: Task<Void, Never>?

    var canSubmit: Bool {
        if isSubmitting { return false }
        guard phone.count == 11 else { return false }
        switch mode {
        case .password: return !pin.isEmpty
        case .sms: return !pin.isEmpty && !smsCode.isEmpty
        }
    }

    // MARK: - 控车码登录

    func login(appState: AppState) {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        infoMessage = nil
        Task {
            defer { isSubmitting = false }
            do {
                // 白名单/封禁预检（与网页版一致）
                let check = try await AuthService.checkPhone(phone)
                if check.blocked {
                    errorMessage = check.message ?? "该手机号已被限制使用"
                    return
                }
                if check.unauthorized {
                    errorMessage = check.message ?? "该手机号未授权，请联系站长开通"
                    return
                }
                let credentials = try await AuthService.login(phone: phone, pin: pin)
                appState.loginCompleted(credentials)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - 短信注册

    func sendCode() {
        guard phone.count == 11, cooldown == 0 else { return }
        errorMessage = nil
        infoMessage = nil
        Task {
            do {
                try await AuthService.sendSMSCode(phone)
                infoMessage = "验证码已发送"
                startCooldown()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func register(appState: AppState) {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        infoMessage = nil
        Task {
            defer { isSubmitting = false }
            do {
                let credentials = try await AuthService.register(phone: phone, code: smsCode, pin: pin)
                appState.loginCompleted(credentials)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func submit(appState: AppState) {
        switch mode {
        case .password: login(appState: appState)
        case .sms: register(appState: appState)
        }
    }

    // MARK: - 验证码倒计时

    private func startCooldown() {
        cooldown = 60
        cooldownTask?.cancel()
        cooldownTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                if self.cooldown > 0 {
                    self.cooldown -= 1
                } else {
                    return
                }
            }
        }
    }
}
