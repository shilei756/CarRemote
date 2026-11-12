import SwiftUI
import CarCore

/// 执行回执：每条指令常驻显示「指令 · 结果 · 时间」，控车有确定性反馈。
/// 与源作品的「演示 · 未发送到车辆」相反，这里全部是真下发结果。
struct CakocheReceipt: Identifiable {
    let id = UUID()
    let command: String
    let ok: Bool
    let detail: String
    let at: Date

    var timeText: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: at)
    }
}

@MainActor
final class CakocheControl: ObservableObject {
    @Published var receipt: CakocheReceipt?
    @Published var executing: CarCommand?

    /// 下发一条真实指令。空调走网站「新版空调通道」（newAC / 开放平台），其余走车联网指令通道。
    /// 1.2.4：判定与 Siri、小组件统一收敛到 `ACService.useNewChannel()`，
    /// CAKOCHE 恒定使用新版通道，授权直接由站主网站下发。
    func run(_ command: CarCommand, temperature: Int? = nil) async {
        guard let credentials = SharedStore.loadCredentials() else {
            receipt = CakocheReceipt(command: command.displayName, ok: false,
                                     detail: "未登录", at: Date())
            return
        }
        guard executing == nil else { return }
        executing = command
        defer { executing = nil }
        let isAC = command == .openAir || command == .closeAir
        do {
            let result: CommandResult
            if isAC, ACService.useNewChannel() {
                result = try await ACService.executeOfficial(command: command,
                                                             credentials: credentials,
                                                             temperature: temperature)
            } else {
                result = try await CarService.execute(command: command, credentials: credentials)
            }
            receipt = CakocheReceipt(
                command: command.displayName,
                ok: result.ok,
                detail: result.ok ? "已下发至车辆" : Self.detail(for: result, isAC: isAC),
                at: Date()
            )
        } catch {
            receipt = CakocheReceipt(command: command.displayName, ok: false,
                                     detail: Self.detail(for: error.localizedDescription, isAC: isAC),
                                     at: Date())
        }
    }

    /// 新版空调需要网站先开通授权。失败信息里的诊断串对用户无意义，
    /// 命中「未开通 / 凭证 / 服务未注册」时给出可操作的引导，而不是一串码。
    static func detail(for result: CommandResult, isAC: Bool) -> String {
        detail(for: result.message, isAC: isAC)
    }

    static func detail(for raw: String, isAC: Bool) -> String {
        guard isAC else { return raw }
        let needsAuth = ["开通", "凭证", "授权", "40001", "refresh", "未注册", "scope"]
            .contains { raw.localizedCaseInsensitiveContains($0) }
        if needsAuth {
            return "新版空调尚未在网站完成授权，请到「我的 → 新版空调授权」扫码开通或直接同步网站授权"
        }
        return raw
    }
}
