import Foundation
import UserNotifications
import CarCore

// MARK: - 车辆异常持续提醒（本地通知）
//
// 需求：检测到「门未锁 / 窗未关 / 天窗未关」等异常，若 10 分钟后依旧异常就通知用户。
//
// iOS 现实约束：App 进入后台后无法持续轮询车况（没有静默推送 / 后台音频等常驻权限），
// 因此采用「本地通知预约 + 状态恢复自动取消」的方案：
//  1. 每次车况刷新（前台 30s 轮询 / 下拉 / 回前台）判断异常项；
//  2. 首次发现异常 → 预约一条 10 分钟后的本地通知，并把异常起始时间写入共享存储；
//  3. 10 分钟内只要 App 再拿到一次「已恢复正常」的车况 → 立刻取消这条预约；
//  4. 若期间 App 一直不在前台，系统仍会按时弹出通知（本地通知由系统托管，不依赖 App 存活）。
//  5. 同一轮异常只提醒一次（避免每 30 秒重复预约），异常解除后可重新武装。
//
// 权限：遵循 Apple HIG，不在启动时请求；仅当用户在「我的 → 车辆异常提醒」打开开关时请求。

enum VehicleAlertService {

    private static let notificationID = "carremote.vehicle.abnormal"
    private static let delay: TimeInterval = 10 * 60

    /// 异常持续 10 分钟后提醒。enabled 来自 AppSettings.vehicleAlertEnabled。
    /// 应在每次车况刷新成功后调用（幂等，内部去重）。
    static func evaluate(status: CarStatus, enabled: Bool) {
        guard enabled else {
            cancelPending(reason: "开关已关闭")
            return
        }
        let reasons = abnormalReasons(status)
        guard !reasons.isEmpty else {
            // 车辆恢复正常：取消尚未送达的提醒，并允许下一轮异常重新武装
            cancelPending(reason: "车辆已恢复正常")
            return
        }

        // 已有一轮未解除的异常预约 → 不重复预约
        if SharedStore.loadVehicleAlertSince() != nil { return }

        // 记录本轮异常起点，预约 10 分钟后提醒
        SharedStore.saveVehicleAlertSince(Date())
        SharedStore.saveVehicleAlertReasons(reasons)

        requestAuthorizationIfNeeded { granted in
            guard granted else { return }
            scheduleNotification(reasons: reasons)
        }
    }

    /// 用户在设置页首次打开开关时调用（上下文驱动，不在启动时请求）
    static func requestAuthorizationOnEnable(completion: @escaping (Bool) -> Void = { _ in }) {
        requestAuthorizationIfNeeded(completion: completion)
    }

    // MARK: - 私有

    private static func requestAuthorizationIfNeeded(completion: @escaping (Bool) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { completion(true) }
            case .denied:
                DispatchQueue.main.async { completion(false) }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    DispatchQueue.main.async { completion(granted) }
                }
            @unknown default:
                DispatchQueue.main.async { completion(false) }
            }
        }
    }

    private static func scheduleNotification(reasons: [String]) {
        let content = UNMutableNotificationContent()
        content.title = "车辆状态异常提醒"
        content.body = "\(reasons.joined(separator: "、"))，已持续 10 分钟，请及时检查车辆。"
        content.sound = .default
        content.badge = 1
        content.userInfo = ["type": "vehicle_abnormal", "reasons": reasons]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { print("[VehicleAlert] 预约通知失败: \(error.localizedDescription)") }
        }
    }

    private static func cancelPending(reason: String) {
        SharedStore.saveVehicleAlertSince(nil)
        SharedStore.saveVehicleAlertReasons([])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
        // 同时清掉可能已送达但用户未处理的角标
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationID])
        print("[VehicleAlert] 取消提醒: \(reason)")
    }

    /// 当前异常项（与车况徽章 / 3D 车模门窗联动同源）
    private static func abnormalReasons(_ status: CarStatus) -> [String] {
        var result: [String] = []
        if status.doorUnlocked { result.append("车门/后备箱/前机盖未锁") }
        if status.windowOpen { result.append("车窗未关") }
        if status.sunroofOpen { result.append("天窗未关") }
        return result
    }
}

// MARK: - 通知前台展示（可选：App 在前台时也弹横幅）

final class VehicleAlertNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = VehicleAlertNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        if #available(iOS 14.0, *) {
            completionHandler([.banner, .list, .sound, .badge])
        } else {
            completionHandler([.alert, .sound, .badge])
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // 点击通知直接回到控车页，方便用户一键查看/处理
        NotificationCenter.default.post(name: .vehicleAlertTapped, object: nil)
        completionHandler()
    }
}

extension Notification.Name {
    static let vehicleAlertTapped = Notification.Name("carremote.vehicleAlertTapped")
}
