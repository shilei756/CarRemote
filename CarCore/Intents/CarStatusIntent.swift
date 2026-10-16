import AppIntents
import WidgetKit
import Foundation

/// 查询车况（Siri / 快捷指令复用）。
/// 执行后会刷新本地快照，桌面小组件同步更新。
public struct CarStatusIntent: AppIntent {
    public static var title: LocalizedStringResource = "查询车况"
    public static var description: IntentDescription = "查询车辆续航、油量、里程与安全状态"
    public static var openAppWhenRun: Bool = false

    public init() {}

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let credentials = SharedStore.loadCredentials() else {
            return .result(dialog: IntentDialog(stringLiteral: "请先在「长安控车」App 中登录"))
        }
        do {
            let (status, car, updatedCredentials) = try await CarService.refresh(credentials: credentials)
            SharedStore.saveCredentials(updatedCredentials)
            SharedStore.saveStatusSnapshot(StatusSnapshot(carName: car.displayName, status: status))
            WidgetCenter.shared.reloadAllTimelines()

            let range = CarStatus.format(status.remainingRangeKm, unit: "公里")
            let fuel = CarStatus.format(status.fuelLeftLiters, unit: "升")
            let odo = CarStatus.format(status.totalOdometerKm, unit: "公里")
            let state = status.stateFlags.summaryText
            let message = "\(car.displayName)：剩余续航 \(range)，油量 \(fuel)，总里程 \(odo)，\(state)"
            return .result(dialog: IntentDialog(stringLiteral: message))
        } catch {
            return .result(dialog: IntentDialog(stringLiteral: "查询失败：\(error.localizedDescription)"))
        }
    }
}
