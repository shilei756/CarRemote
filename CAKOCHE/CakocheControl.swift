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

    /// 下发一条真实指令。空调走开放平台通道，其余走车联网指令通道。
    func run(_ command: CarCommand, temperature: Int? = nil) async {
        guard let credentials = SharedStore.loadCredentials() else {
            receipt = CakocheReceipt(command: command.displayName, ok: false,
                                     detail: "未登录", at: Date())
            return
        }
        guard executing == nil else { return }
        executing = command
        defer { executing = nil }
        do {
            let result: CommandResult
            if command == .openAir || command == .closeAir {
                result = try await ACService.executeOfficial(command: command,
                                                             credentials: credentials,
                                                             temperature: temperature)
            } else {
                result = try await CarService.execute(command: command, credentials: credentials)
            }
            receipt = CakocheReceipt(
                command: command.displayName,
                ok: result.ok,
                detail: result.ok ? "已下发至车辆" : result.message,
                at: Date()
            )
        } catch {
            receipt = CakocheReceipt(command: command.displayName, ok: false,
                                     detail: error.localizedDescription, at: Date())
        }
    }
}
