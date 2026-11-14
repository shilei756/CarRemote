import AppIntents

/// Siri 高危操作统一确认（点火 / 熄火 / 开锁 / 闭锁等）。
///
/// 两个系统分支：
/// - iOS 18+：`requestConfirmation(conditions:actionName:dialog:)`（现行 API）
/// - iOS 16/17：`requestConfirmation(output:confirmationActionName:showPrompt:)`
///   （已废弃但功能完整，iOS 16 起可用，废弃警告无副作用）
///
/// 用户取消时该方法会抛出错误，意图随之结束，指令不会下发。
///
/// 公开：Intent 声明放在 App 目标（App Intents 元数据只对 App / Extension 目标抽取），
/// 逻辑放在框架里，跨模块调用需要 public。
@available(iOS 16.0, *)
public extension AppIntent {
    func confirmDangerous(_ dialog: IntentDialog) async throws {
        if #available(iOS 18.0, *) {
            try await requestConfirmation(conditions: [], actionName: .continue, dialog: dialog)
        } else {
            try await requestConfirmation(
                output: .result(dialog: dialog),
                confirmationActionName: .continue,
                showPrompt: true
            )
        }
    }
}
