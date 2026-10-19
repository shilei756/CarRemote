import AppIntents

/// Siri 高危操作统一确认（点火 / 熄火 / 开锁 / 闭锁等）。
///
/// 两个系统分支：
/// - iOS 18+：`requestConfirmation(conditions:actionName:dialog:)`（现行 API）
/// - iOS 16/17：`requestConfirmation(output:confirmationActionName:showPrompt:)`
///   （已废弃但功能完整，iOS 16 起可用，废弃警告无副作用）
///
/// 用户取消时该方法会抛出错误，意图随之结束，指令不会下发。
@available(iOS 16.0, *)
extension AppIntent {
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
