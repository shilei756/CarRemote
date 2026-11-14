import AppIntents
import WidgetKit
import Foundation

/// 控车 Intent 的公共执行逻辑（App / 小组件 / 快捷指令三处共用）。
///
/// 声明放在 CarCore 框架里，但**Intent 本体放在 App 目标**：
/// App Intents 的元数据只对「App / App Extension 目标」自动抽取，
/// 框架内的 Intent 需要 iOS 17 的 AppIntentsPackage 才能被发现，
/// 放 App 目标可保证 iOS 16 起在「快捷指令」里一搜就有。
public enum CarIntentRunner {

    /// 指令执行结果：ok = 车机平台是否接受；speech = 成功/失败明确播报文本
    public struct Outcome {
        public let ok: Bool
        public let speech: String

        public init(ok: Bool, speech: String) {
            self.ok = ok
            self.speech = speech
        }
    }

    /// 执行一条控车指令。
    /// - Parameter temperature: 仅「开空调」使用（16~32℃，车机按 1℃ 取整）
    public static func run(command: CarCommand, temperature: Int? = nil) async -> Outcome {
        let settings = SharedStore.loadSettings()
        guard settings.siriAllows(command: command) else {
            return Outcome(ok: false, speech: "「\(command.displayName)」尚未在 App 的设置中开放")
        }
        guard let credentials = SharedStore.loadCredentials() else {
            return Outcome(ok: false, speech: "请先在 App 内登录（手机号 + 控车码）")
        }
        do {
            // 空调与 App 内保持一致：新版模式走开放平台链路。
            // 1.2.4：判定收敛到 ACService.useNewChannel()，正式版仍按用户设置的 acMode。
            let isAC = (command == .openAir || command == .closeAir)
            let result: CommandResult
            if isAC, ACService.useNewChannel() {
                result = try await ACService.executeOfficial(command: command,
                                                            credentials: credentials,
                                                            temperature: temperature)
            } else {
                result = try await CarService.execute(command: command, credentials: credentials)
            }
            WidgetCenter.shared.reloadAllTimelines()
            if result.ok {
                return Outcome(ok: true, speech: successSpeech(command: command, temperature: temperature))
            }
            return Outcome(ok: false, speech: "\(command.displayName)失败：\(cleanReason(result.message))")
        } catch {
            return Outcome(ok: false, speech: "\(command.displayName)失败：\(cleanReason(error.localizedDescription))")
        }
    }

    /// 成功播报：空调额外带温度，其余为「指令 + 成功」
    public static func successSpeech(command: CarCommand, temperature: Int?) -> String {
        if command == .openAir, let temperature {
            return "空调已开启，设定 \(temperature) 摄氏度"
        }
        return "\(command.displayName)成功"
    }

    /// 失败原因清洗：取首行去空白，空则给默认文案（避免播报裸 error 或空串）
    public static func cleanReason(_ raw: String) -> String {
        let firstLine = raw.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "请检查网络后重试" : trimmed
    }
}
